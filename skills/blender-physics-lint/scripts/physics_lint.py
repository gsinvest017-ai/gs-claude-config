"""physics_lint.py — Blender 場景物理 linter（給 LLM 建模迴圈當 gate）。

三檢，對應「LLM 盲寫座標」最常見的三種物理常識錯誤：
  A intersect — BVHTree 兩兩重疊找穿透對（含 bbox 完全包含的疑似案）
  B floating  — 底面樣本點向下 ray_cast 檢懸空（重力常識）
  C settle    — rigid body 模擬 N frames 比對位移/轉動（放下去會不會倒）

設計要點：
  - 貼合接觸（機櫃並排、物體放在地板上）不是穿透：BVH 用世界座標頂點向質心
    收縮 0.999 再建，毫米級以下的接觸不報。
  - settle 只跑「通過 A、B 的物件」：穿透中的物體進 rigid body 模擬會爆飛，
    懸空物必然位移，都會污染判定。先修 A/B 再驗 C。
  - settle 跑在「烘平 scale 的臨時複製體」上再整批刪除：非均勻 object scale 會讓
    Bullet 碰撞形狀失真，且原物件全程不被 rigid body / 動畫系統碰到（零場景污染）。
  - 碰撞 margin 雙邊都收到 1mm：Blender 預設 margin 0.04，「剛好貼地」的物件開場
    就嵌入 4cm 會被彈射，貼地箱實測位移 0.28m+31°（Blender 5.1 headless 踩雷）。
  - 支撐物（floor/ground/wall/… 命名，或大而薄的板）當 PASSIVE、不檢懸空。

用法：
  1. Blender MCP：把本檔全文貼進 execute_blender_code，再呼叫
     `run_lint()`（回傳 dict，stdout 也會印 PHYSICS_LINT_RESULT: JSON）。
  2. headless：blender --background --your.blend --python physics_lint.py

輸出 JSON schema：
  {"ok": bool, "checked": [names], "skipped_settle": [names],
   "violations": [{"check": "intersect|containment|floating|unstable",
                   "objects": [...], "detail": "...", "suggestion": "..."}]}
"""

import json
import math
import re

import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

SUPPORT_NAME_RE = re.compile(
    r"(floor|ground|wall|ceil|room|plane|terrain|base|slab)", re.I
)
SHRINK = 0.999          # BVH 頂點向質心收縮比例（貼合接觸免報）
GAP_EPS = 0.01          # 懸空判定：底面離下方支撐 > 1cm 才報
MOVE_EPS = 0.05         # settle：位移 > 5cm 判 unstable
ROT_EPS_DEG = 10.0      # settle：轉動 > 10° 判 unstable
SETTLE_FRAMES = 30


def _mesh_objects():
    return [o for o in bpy.context.scene.objects
            if o.type == "MESH" and o.visible_get()]


def _is_support(obj):
    """地板/牆/天花板等支撐物：靠命名，或「大而薄的板」heuristic。"""
    if SUPPORT_NAME_RE.search(obj.name):
        return True
    dims = sorted(obj.dimensions)
    return dims[2] > 2.0 and dims[0] < 0.02 * dims[2]


def _world_bbox(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mins = Vector((min(v[i] for v in corners) for i in range(3)))
    maxs = Vector((max(v[i] for v in corners) for i in range(3)))
    return mins, maxs


def _aabb_overlap(a, b):
    (amin, amax), (bmin, bmax) = a, b
    return all(amin[i] <= bmax[i] and bmin[i] <= amax[i] for i in range(3))


def _aabb_contains(outer, inner):
    (omin, omax), (imin, imax) = outer, inner
    return all(omin[i] <= imin[i] and imax[i] <= omax[i] for i in range(3))


def _bvh(obj, depsgraph):
    """世界座標、向質心收縮後的 BVHTree。"""
    eval_obj = obj.evaluated_get(depsgraph)
    mesh = eval_obj.to_mesh()
    try:
        mw = eval_obj.matrix_world
        verts = [mw @ v.co for v in mesh.vertices]
        if not verts:
            return None
        center = Vector()
        for v in verts:
            center += v
        center /= len(verts)
        verts = [center + (v - center) * SHRINK for v in verts]
        polys = [tuple(p.vertices) for p in mesh.polygons]
        if not polys:
            return None
        return BVHTree.FromPolygons([tuple(v) for v in verts], polys)
    finally:
        eval_obj.to_mesh_clear()


def _inside(tree, pt, max_iter=32):
    """射線奇偶性判定點是否在（近似封閉的）mesh 體積內。"""
    count = 0
    origin = pt.copy()
    direction = Vector((0.0, 0.0, 1.0))
    for _ in range(max_iter):
        loc = tree.ray_cast(origin, direction)[0]
        if loc is None:
            break
        count += 1
        origin = loc + direction * 1e-5
    return count % 2 == 1


PEN_EPS = 0.002  # 體積互滲判定：AABB 三軸互滲深度都要 > 2mm


def check_intersect(objs, depsgraph):
    """A：兩兩穿透（表面交疊 或 體積互滲）+ bbox 完全包含。回傳 violations list。

    表面交疊抓不到「同截面互插」（如兩個等高機櫃沿 x 互插——表面只在邊緣線相交，
    收縮後為零），所以補體積互滲：AABB 三軸互滲深度都 > PEN_EPS，且交集中心點
    以射線奇偶性驗證同時在兩物件內部。完全包含（房間殼裝機櫃）另列軟警告。
    """
    violations = []
    boxes = {o.name: _world_bbox(o) for o in objs}
    trees = {}
    for i, a in enumerate(objs):
        for b in objs[i + 1:]:
            if not _aabb_overlap(boxes[a.name], boxes[b.name]):
                continue
            for o in (a, b):
                if o.name not in trees:
                    trees[o.name] = _bvh(o, depsgraph)
            ta, tb = trees[a.name], trees[b.name]
            if ta is None or tb is None:
                continue
            (amin, amax), (bmin, bmax) = boxes[a.name], boxes[b.name]
            contained = (_aabb_contains(boxes[a.name], boxes[b.name]) or
                         _aabb_contains(boxes[b.name], boxes[a.name]))
            pairs = ta.overlap(tb)
            if pairs:
                violations.append({
                    "check": "intersect",
                    "objects": [a.name, b.name],
                    "detail": f"{len(pairs)} 對三角面互相穿透",
                    "suggestion": "拉開兩物件位置或縮小尺寸；並排貼合請保留 >1mm 間隙",
                })
                continue
            if not contained:
                pen = [min(amax[i2], bmax[i2]) - max(amin[i2], bmin[i2])
                       for i2 in range(3)]
                if all(p > PEN_EPS for p in pen):
                    center = Vector((
                        (max(amin[i2], bmin[i2]) + min(amax[i2], bmax[i2])) / 2
                        for i2 in range(3)))
                    if _inside(ta, center) and _inside(tb, center):
                        violations.append({
                            "check": "intersect",
                            "objects": [a.name, b.name],
                            "detail": (f"體積互滲 {pen[0]:.3f}×{pen[1]:.3f}"
                                       f"×{pen[2]:.3f} m（表面無交疊的同截面互插）"),
                            "suggestion": "拉開兩物件位置；並排貼合請保留 >1mm 間隙",
                        })
            else:
                violations.append({
                    "check": "containment",
                    "objects": [a.name, b.name],
                    "detail": "一物件的 bounding box 完全包在另一物件內",
                    "suggestion": "確認是否誤把物件擺進另一物件內部；容器類（房間殼）可忽略",
                })
    return violations


def check_floating(objs, depsgraph):
    """B：底面 5 樣本點向下 ray_cast，找不到 <= GAP_EPS 的支撐即懸空。"""
    scene = bpy.context.scene
    violations = []
    for obj in objs:
        if _is_support(obj):
            continue
        mins, maxs = _world_bbox(obj)
        if mins.z <= GAP_EPS:          # 貼地（或插進地板——那是 A 的事）
            continue
        cx, cy = (mins.x + maxs.x) / 2, (mins.y + maxs.y) / 2
        dx, dy = (maxs.x - mins.x) * 0.4, (maxs.y - mins.y) * 0.4
        samples = [(cx, cy), (cx - dx, cy - dy), (cx + dx, cy - dy),
                   (cx - dx, cy + dy), (cx + dx, cy + dy)]
        best_gap = None
        supported = False
        for x, y in samples:
            origin = Vector((x, y, mins.z - 1e-4))
            hit = scene.ray_cast(depsgraph, origin, Vector((0, 0, -1)))
            if hit[0]:
                gap = origin.z - hit[1].z
                best_gap = gap if best_gap is None else min(best_gap, gap)
                if gap <= GAP_EPS:
                    supported = True
                    break
        if not supported:
            detail = (f"底面離下方最近表面 {best_gap:.3f} m"
                      if best_gap is not None else "下方沒有任何物體")
            violations.append({
                "check": "floating",
                "objects": [obj.name],
                "detail": detail,
                "suggestion": "沿 -Z 下移使底面貼到支撐面（on_top_of），或補上支撐物",
            })
    return violations


def _add_rigid_body(obj, body_type):
    """背景模式相容的 rigid body 掛載：先試 ops+temp_override，失敗走 collection link。"""
    scene = bpy.context.scene
    if obj.rigid_body is not None:
        obj.rigid_body.type = body_type
        return True
    try:
        with bpy.context.temp_override(object=obj, active_object=obj,
                                       selected_objects=[obj]):
            bpy.ops.rigidbody.object_add()
    except Exception:
        rbw = scene.rigidbody_world
        if rbw and rbw.collection and obj.name not in rbw.collection.objects:
            rbw.collection.objects.link(obj)
        bpy.context.view_layer.update()
    if obj.rigid_body is None:
        return False
    obj.rigid_body.type = body_type
    if body_type == "PASSIVE":
        # 支撐物常是 plane / 薄板：CONVEX_HULL 對零厚度形狀退化（物件會直接穿過），
        # 靜態物用 MESH 才有正確碰撞面。
        obj.rigid_body.collision_shape = "MESH"
    else:
        obj.rigid_body.collision_shape = "CONVEX_HULL"
    # 預設 margin 0.04 會讓「剛好貼地」的物件開場嵌入 4cm 被彈射，雙邊都收到 1mm
    obj.rigid_body.use_margin = True
    obj.rigid_body.collision_margin = 0.001
    return True


def check_settle(objs, skip_names, frames=SETTLE_FRAMES):
    """C：rigid body 模擬 frames 格，比對位移/轉動。回傳 (violations, skipped)。

    模擬跑在「烘平 scale 的臨時複製體」上，量測後整批刪除；原物件全程不掛
    rigid body、不改 transform。
    """
    scene = bpy.context.scene
    candidates = [o for o in objs
                  if o.name not in skip_names and not _is_support(o)]
    supports = [o for o in objs if _is_support(o)]
    skipped = sorted(skip_names)
    if not candidates:
        return [], skipped

    had_rbw = scene.rigidbody_world is not None
    if not had_rbw:
        bpy.ops.rigidbody.world_add()
    rbw = scene.rigidbody_world
    if rbw.collection is None:
        rbw.collection = bpy.data.collections.new("RigidBodyWorld")

    temp_objs, temp_meshes = [], []

    def _dup(o):
        d = o.copy()
        d.data = o.data.copy()
        d.name = o.name + ".pl_sim"
        scene.collection.objects.link(d)
        temp_objs.append(d)
        temp_meshes.append(d.data)
        sx, sy, sz = d.scale
        if (sx, sy, sz) != (1.0, 1.0, 1.0):
            d.data.transform(Matrix.Diagonal((sx, sy, sz, 1.0)))
            d.scale = (1.0, 1.0, 1.0)
        return d

    tracked = {}                       # 原物件名 -> 複製體
    for o in candidates:
        d = _dup(o)
        if _add_rigid_body(d, "ACTIVE"):
            tracked[o.name] = d
    for o in supports:
        _add_rigid_body(_dup(o), "PASSIVE")
    bpy.context.view_layer.update()
    snapshot = {n: d.matrix_world.copy() for n, d in tracked.items()}

    old_start, old_end = scene.frame_start, scene.frame_end
    old_pc = (rbw.point_cache.frame_start, rbw.point_cache.frame_end)
    scene.frame_start = 1
    scene.frame_end = max(old_end, frames)
    rbw.point_cache.frame_start = 1
    rbw.point_cache.frame_end = frames

    violations = []
    try:
        for f in range(1, frames + 1):
            scene.frame_set(f)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for name, d in tracked.items():
            m_final = d.evaluated_get(depsgraph).matrix_world
            m_orig = snapshot[name]
            dpos = (m_final.translation - m_orig.translation).length
            ang = math.degrees(
                m_orig.to_quaternion().rotation_difference(
                    m_final.to_quaternion()).angle)
            if dpos > MOVE_EPS or ang > ROT_EPS_DEG:
                violations.append({
                    "check": "unstable",
                    "objects": [name],
                    "detail": f"重力模擬 {frames} 格後位移 {dpos:.3f} m、轉動 {ang:.1f}°",
                    "suggestion": "物件重心超出支撐面（傾倒/滑落）；調整姿態或移到穩定支撐上",
                })
    finally:
        scene.frame_set(1)
        for d in temp_objs:
            bpy.data.objects.remove(d, do_unlink=True)
        for me in temp_meshes:
            try:
                bpy.data.meshes.remove(me)
            except Exception:
                pass
        if not had_rbw:
            try:
                bpy.ops.rigidbody.world_remove()
            except Exception:
                pass
        else:
            rbw.point_cache.frame_start, rbw.point_cache.frame_end = old_pc
        scene.frame_start, scene.frame_end = old_start, old_end
        bpy.context.view_layer.update()
    return violations, skipped


def run_lint(checks=("intersect", "floating", "settle"), settle_frames=SETTLE_FRAMES):
    """跑三檢，回傳 report dict；stdout 印 PHYSICS_LINT_RESULT: JSON 供解析。"""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    objs = _mesh_objects()
    violations = []
    skipped_settle = []

    if "intersect" in checks:
        violations += check_intersect(objs, depsgraph)
    if "floating" in checks:
        violations += check_floating(objs, depsgraph)
    if "settle" in checks:
        flagged = {name for v in violations for name in v["objects"]}
        settle_violations, skipped_settle = check_settle(
            objs, flagged, frames=settle_frames)
        violations += settle_violations

    report = {
        "ok": not violations,
        "checked": sorted(o.name for o in objs),
        "skipped_settle": skipped_settle,
        "violations": violations,
    }
    print("PHYSICS_LINT_RESULT: " + json.dumps(report, ensure_ascii=False))
    return report


if __name__ == "__main__":
    run_lint()
