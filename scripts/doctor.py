#!/usr/bin/env python3
"""gs-claude-config doctor — cross-platform health check for skill sync.

Diagnoses the exact failure modes that broke the Windows -> Mac Studio
migration on 2026-07-01:

  1. working on a non-default branch (skills land on a feature branch while
     ``main`` — the branch other machines clone — lags behind);
  2. unpushed commits (skills committed locally but never pushed to origin);
  3. uncommitted skills (new skill dirs never ``git add``-ed, or edited
     SKILL.md files not committed);
  4. skills present in the working tree but missing on ``origin/<default>``
     (so a fresh ``git clone`` / ``git pull`` on another host can't see them);
  5. broken symlinks under ``skills/`` / ``commands/`` (the sibling
     ``quant-research-skill`` repo is missing, so linked skills dangle).

Read-only by default: it queries git and prints a report with suggested
fix commands. It never commits, pushes, or edits anything.

Runs on Windows / macOS / Linux with only the standard library + ``git``.

    python scripts/doctor.py                # full report (fetches first)
    python scripts/doctor.py --no-fetch     # skip network, use cached refs
    python scripts/doctor.py --json         # machine-readable summary
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys

# Make emoji / Chinese output survive a cp950 (Windows) console.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OK = "✅"      # white check mark
WARN = "⚠️"   # warning sign
FAIL = "❌"    # cross mark
INFO = "\U0001f50d"  # magnifying glass


def git(*args: str) -> tuple[int, str]:
    """Run ``git -C <repo> <args>``; return (returncode, stripped stdout)."""
    try:
        p = subprocess.run(
            ["git", "-C", REPO_DIR, *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        print(f"{FAIL} git 不在 PATH 上——請先安裝 git。")
        sys.exit(2)
    return p.returncode, (p.stdout or "").strip()


def default_branch() -> str:
    """The branch other machines clone. Prefer origin/HEAD, fall back to main."""
    code, out = git("symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if code == 0 and out:
        return out.rsplit("/", 1)[-1]
    for cand in ("main", "master"):
        if git("rev-parse", "--verify", "--quiet", f"origin/{cand}")[0] == 0:
            return cand
    return "main"


def skills_in_tree(ref: str) -> set[str]:
    """Top-level skill names present under skills/ at a git ref."""
    code, out = git("ls-tree", "--name-only", ref, "skills/")
    if code != 0 or not out:
        return set()
    return {line.split("/", 1)[1] for line in out.splitlines() if "/" in line}


def skills_on_disk() -> set[str]:
    root = os.path.join(REPO_DIR, "skills")
    if not os.path.isdir(root):
        return set()
    return {name for name in os.listdir(root)
            if not name.startswith(".")}


class Report:
    """Collects per-check results and drives the exit code."""

    def __init__(self) -> None:
        self.checks: list[dict] = []
        self.worst = 0  # 0 ok, 1 warn, 2 fail

    def add(self, level: str, title: str, detail: str = "", fix: str = "") -> None:
        icon = {"ok": OK, "warn": WARN, "fail": FAIL}[level]
        self.checks.append(
            {"level": level, "title": title, "detail": detail, "fix": fix}
        )
        self.worst = max(self.worst, {"ok": 0, "warn": 1, "fail": 2}[level])
        print(f"\n{icon} {title}")
        if detail:
            for line in detail.splitlines():
                print(f"    {line}")
        if fix:
            print("    修法：")
            for line in fix.splitlines():
                print(f"      {line}")


def check_branch(rep: Report, default: str) -> None:
    _, cur = git("rev-parse", "--abbrev-ref", "HEAD")
    if cur == default:
        rep.add("ok", f"分支：在 {default} 上（其他機器 clone 的分支）")
    else:
        rep.add(
            "warn",
            f"分支：目前在 `{cur}`，不是預設分支 `{default}`",
            "在非預設分支上新增的 skill，其他機器 `git clone` / `git pull` 拿不到。\n"
            "這正是這次 Mac Studio 少了一堆 skill 的主因。",
            f"確認 `{cur}` 已含 `{default}` 後 fast-forward 上去：\n"
            f"git checkout {default} && git merge --ff-only {cur} && git push origin {default}",
        )


def check_uncommitted(rep: Report) -> None:
    _, out = git("status", "--porcelain", "--", "skills/", "commands/", "agents/")
    if not out:
        rep.add("ok", "未提交變更：skills/ commands/ agents/ 都乾淨")
        return
    untracked, modified = [], []
    for line in out.splitlines():
        status, path = line[:2], line[3:]
        (untracked if "?" in status else modified).append(path)
    detail = []
    if untracked:
        detail.append("未追蹤（從沒 git add）：")
        detail += [f"  - {p}" for p in untracked]
    if modified:
        detail.append("已修改未提交：")
        detail += [f"  - {p}" for p in modified]
    rep.add(
        "warn",
        f"未提交變更：{len(untracked)} 個未追蹤、{len(modified)} 個已修改",
        "\n".join(detail),
        "掃過內容確認無祕密後提交：\n"
        "git add skills/ commands/ agents/ && git commit -m \"新增/更新 skill\"",
    )


def check_unpushed(rep: Report, default: str) -> None:
    upstream = f"origin/{default}"
    if git("rev-parse", "--verify", "--quiet", upstream)[0] != 0:
        rep.add("warn", f"未推送：找不到 {upstream}（尚未 fetch？）")
        return
    _, out = git("rev-list", "--count", f"{upstream}..HEAD")
    ahead = int(out or "0")
    if ahead == 0:
        rep.add("ok", f"未推送：HEAD 沒有領先 {upstream} 的 commit")
        return
    _, commits = git("log", "--oneline", f"{upstream}..HEAD")
    _, files = git("diff", "--name-only", f"{upstream}..HEAD", "--", "skills/")
    touched = sorted({line.split("/", 1)[1].split("/", 1)[0]
                      for line in files.splitlines() if "/" in line})
    detail = [f"本機領先 {upstream} {ahead} 個 commit（尚未 push）：", commits]
    if touched:
        detail.append(f"其中動到的 skill：{', '.join(touched)}")
    rep.add(
        "warn",
        f"未推送：{ahead} 個 commit 卡在本機",
        "\n".join(detail),
        f"git push origin HEAD:{default}",
    )


def check_remote_parity(rep: Report, default: str) -> None:
    upstream = f"origin/{default}"
    if git("rev-parse", "--verify", "--quiet", upstream)[0] != 0:
        rep.add("warn", f"遠端對照：找不到 {upstream}，跳過")
        return
    local = skills_in_tree("HEAD")
    remote = skills_in_tree(upstream)
    missing = sorted(local - remote)
    if not missing:
        rep.add(
            "ok",
            f"遠端對照：{len(remote)} 個 skill 在 {upstream} 上都齊了",
        )
        return
    rep.add(
        "fail",
        f"遠端對照：{len(missing)} 個 skill 在本機有、{upstream} 沒有",
        "其他機器現在拉不到這些 skill：\n"
        + "\n".join(f"  - {s}" for s in missing),
        "先處理上面的「未提交」「未推送」再重跑本檢查；\n"
        f"全部推到 {default} 後這裡就會轉綠。",
    )


def _link_is_broken(path: str) -> bool:
    """A symlink is broken only if neither native nor manual resolution finds
    the target. Windows returns a false negative from os.path.exists() on
    relative symlinks with ``..`` + backslash targets, so resolve the readlink
    text against the link's own directory as a fallback before giving up."""
    if os.path.exists(path):
        return False
    target = os.readlink(path)
    if os.path.isabs(target):
        return not os.path.exists(target)
    resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
    return not os.path.exists(resolved)


def check_symlinks(rep: Report) -> None:
    broken: list[str] = []
    for sub in ("skills", "commands"):
        root = os.path.join(REPO_DIR, sub)
        if not os.path.isdir(root):
            continue
        for name in os.listdir(root):
            path = os.path.join(root, name)
            if os.path.islink(path) and _link_is_broken(path):
                target = os.readlink(path)
                broken.append(f"{sub}/{name} -> {target}")
    if not broken:
        rep.add("ok", "符號連結：skills/ commands/ 沒有斷鏈")
        return
    rep.add(
        "fail",
        f"符號連結：{len(broken)} 個斷鏈",
        "\n".join(f"  - {b}" for b in broken),
        "通常是 sibling repo 沒 clone。補上（路徑見 install.sh 的 QRS_REMOTE）：\n"
        "git clone https://github.com/gsinvest017-ai/quant-research-skill.git ~/quant-research-skill",
    )


def main() -> int:
    ap = argparse.ArgumentParser(description="gs-claude-config skill-sync doctor")
    ap.add_argument("--no-fetch", action="store_true",
                    help="不要先 git fetch（用本機快取的 remote refs）")
    ap.add_argument("--json", action="store_true",
                    help="額外輸出機器可讀 JSON 摘要")
    args = ap.parse_args()

    if git("rev-parse", "--is-inside-work-tree")[0] != 0:
        print(f"{FAIL} {REPO_DIR} 不是 git 工作區。")
        return 2

    print(f"{INFO} gs-claude-config doctor")
    print(f"    repo: {REPO_DIR}")

    if not args.no_fetch:
        print("    先 git fetch origin ...")
        git("fetch", "--quiet", "origin")

    default = default_branch()
    rep = Report()

    check_branch(rep, default)
    check_uncommitted(rep)
    check_unpushed(rep, default)
    check_remote_parity(rep, default)
    check_symlinks(rep)

    n_ok = sum(1 for c in rep.checks if c["level"] == "ok")
    n_warn = sum(1 for c in rep.checks if c["level"] == "warn")
    n_fail = sum(1 for c in rep.checks if c["level"] == "fail")
    print("\n" + "-" * 60)
    print(f"總結：{OK} {n_ok}  {WARN} {n_warn}  {FAIL} {n_fail}")
    if rep.worst == 0:
        print("所有 skill 都已同步到遠端，其他機器 git pull 即可拿到全部。")
    else:
        print("有項目需處理——照上面每一項的「修法」跑，再重跑一次 doctor 驗證。")

    if args.json:
        print("\n" + json.dumps(
            {"default_branch": default,
             "worst": rep.worst,
             "checks": rep.checks},
            ensure_ascii=False, indent=2))

    # 0 healthy, 1 warnings, 2 failures — usable as a pre-flight gate.
    return rep.worst


if __name__ == "__main__":
    sys.exit(main())
