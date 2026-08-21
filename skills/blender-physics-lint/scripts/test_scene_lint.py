"""test_scene_lint.py — physics_lint 三檢 headless 自測。

合成一個迷你機房場景（機櫃尺寸沿用 gs-thermal-sim：0.6×1.2×2.0）：
  floor            10×7 地板                     → 支撐物，不檢
  rack_ok          貼地、與鄰櫃「剛好貼合」      → 三檢全過（貼合不是穿透）
  rack_overlap_a/b 兩櫃在 x 方向互插 0.3m        → A intersect 要抓到
  rack_float       底部懸空 0.5m                 → B floating 要抓到
  rack_tilt        傾斜 35°（> 傾倒閾值 ~17°）   → C settle 要判 unstable

跑法：
  blender --background --python test_scene_lint.py
結尾印 SELFTEST PASS / SELFTEST FAIL（非零 exit code）。
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_lint  # noqa: E402

RACK = (0.6, 1.2, 2.0)


def _clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def _box(name, cx, cy, cz, sx, sy, sz):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(cx, cy, cz))
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.scale = (sx, sy, sz)
    return obj


def _build_scene():
    _clear_scene()
    bpy.ops.mesh.primitive_plane_add(size=1, location=(5.0, 3.5, 0.0))
    floor = bpy.context.view_layer.objects.active
    floor.name = "floor"
    floor.scale = (10.0, 7.0, 1.0)

    w, d, h = RACK
    _box("rack_ok", 2.8, 2.0, h / 2, w, d, h)
    _box("rack_overlap_a", 3.4, 2.0, h / 2, w, d, h)   # 與 rack_ok 剛好貼合
    _box("rack_overlap_b", 3.7, 2.0, h / 2, w, d, h)   # 與 a 互插 0.3m
    _box("rack_float", 4.6, 3.5, h / 2 + 0.5, w, d, h)  # 懸空 0.5m

    tilt = _box("rack_tilt", 6.0, 2.0, h / 2, w, d, h)
    tilt.rotation_euler = (0.0, math.radians(35.0), 0.0)
    bpy.context.view_layer.update()
    min_z = min((tilt.matrix_world @ Vector(c)).z for c in tilt.bound_box)
    tilt.location.z -= min_z          # 最低角落貼地
    bpy.context.view_layer.update()


def _fail(msg, report):
    print(f"SELFTEST FAIL: {msg}")
    print(report)
    sys.exit(1)


def main():
    _build_scene()
    report = physics_lint.run_lint()
    by_check = {}
    for v in report["violations"]:
        by_check.setdefault(v["check"], []).append(set(v["objects"]))

    if {"rack_overlap_a", "rack_overlap_b"} not in by_check.get("intersect", []):
        _fail("穿透對 rack_overlap_a/b 沒被抓到", report)
    if any("rack_ok" in objs for objs in
           [set(v["objects"]) for v in report["violations"]]):
        _fail("rack_ok（合法貼合）被誤報", report)
    if {"rack_float"} not in by_check.get("floating", []):
        _fail("懸空 rack_float 沒被抓到", report)
    if {"rack_tilt"} not in by_check.get("unstable", []):
        _fail("傾斜 rack_tilt 沒被判 unstable", report)
    expected_skip = {"rack_overlap_a", "rack_overlap_b", "rack_float"}
    if not expected_skip.issubset(set(report["skipped_settle"])):
        _fail(f"settle 應跳過 {expected_skip}", report)

    tilt = bpy.data.objects["rack_tilt"]
    if abs(math.degrees(tilt.rotation_euler.y) - 35.0) > 1.0:
        _fail("settle 後場景未還原（rack_tilt 姿態被改動）", report)

    print("SELFTEST PASS")


if __name__ == "__main__":
    main()
