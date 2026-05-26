# prog-lang-tutor / data

Runtime storage for the `/prog-lang-tutor` skill. **Not** checked into git
(see `.gitignore` in this dir) — each user analyses their own repos.

## Layout

```
data/
├── .gitignore
├── README.md
└── <repo-slug>/
    └── knowledge.json
```

`<repo-slug>` is `Split-Path -Leaf <repo-path> | lowercase | spaces→_`.
Example: `C:\Users\User\autogo` → `autogo`.

## knowledge.json schema

```json
{
  "repo_path":   "C:\\Users\\User\\autogo",
  "repo_slug":   "autogo",
  "language":    "python",
  "analyzed_at": "2026-05-26T01:09:08Z",
  "knowledge_points": [
    {
      "id":           "py-decorator-001",
      "topic":        "Python @property decorator",
      "category":     "decorator",
      "language":     "python",
      "code_example": "@property\ndef value(self) -> int: ...",
      "where_used":   ["src/state.py:142"],
      "explanation":  "...",
      "why_important":"...",
      "quiz": {
        "question": "為什麼能用 obj.value 而非 obj.value()?",
        "code":     "@property\ndef value(self) -> int: ...",
        "answer":   "..."
      },
      "difficulty":     2,
      "reviewed_count": 0,
      "last_reviewed":  null
    }
  ]
}
```

The top-level `repo_path` / `repo_slug` / `language` / `analyzed_at` fields
are stamped by `scripts/save-knowledge.ps1`; you don't need to include them
when feeding `-KnowledgeJsonPath` — they'll be overwritten.

## Manual edits

Safe to hand-edit `knowledge.json`:
- Remove a knowledge point you don't want quizzed again → delete its object.
- Lower review frequency → bump `reviewed_count` artificially high.
- Reset progress → set `last_reviewed` to `null` and `reviewed_count` to 0.

## Removing a repo's bank

```powershell
Remove-Item -Recurse "$env:USERPROFILE\.claude\skills\prog-lang-tutor\data\<slug>\"
& "$env:USERPROFILE\.claude\skills\prog-lang-tutor\scripts\unschedule-review.ps1" -RepoSlug <slug>
```
