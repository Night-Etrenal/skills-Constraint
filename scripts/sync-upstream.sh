#!/bin/sh
set -eu

UPSTREAM_URL="https://github.com/mattpocock/skills.git"
UPSTREAM_BRANCH="main"
REMOTE_NAME="portfolio-upstream"

root="$(git rev-parse --show-toplevel)"
cd "$root"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Refusing upstream sync: working tree or index is not clean." >&2
  exit 2
fi

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote set-url "$REMOTE_NAME" "$UPSTREAM_URL"
else
  git remote add "$REMOTE_NAME" "$UPSTREAM_URL"
fi

git fetch --no-tags "$REMOTE_NAME" "$UPSTREAM_BRANCH"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
branch="upstream-sync/$stamp"
git switch -c "$branch"

if ! git merge --no-ff --no-commit "$REMOTE_NAME/$UPSTREAM_BRANCH"; then
  echo "Upstream merge has conflicts. Resolve only after reviewing both sides, or run: git merge --abort" >&2
  exit 3
fi

if ! git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  echo "Mirror is already synchronized with upstream."
  exit 0
fi

changed="$(git diff --cached --name-only)"
printf '%s\n' "$changed"

high_risk="$(printf '%s\n' "$changed" | grep -E '^(\.github/workflows/|\.github/actions/|\.codex/|\.agents/|AGENTS\.md$|package(-lock)?\.json$|pnpm-lock\.yaml$|yarn\.lock$|scripts/|skills/.+/scripts/)' || true)"
if [ -n "$high_risk" ] && [ "${ALLOW_HIGH_RISK_UPSTREAM:-0}" != "1" ]; then
  echo "Upstream changed high-risk execution or policy paths:" >&2
  printf '%s\n' "$high_risk" >&2
  echo "The merge was aborted without a commit. Review upstream first, then rerun with ALLOW_HIGH_RISK_UPSTREAM=1." >&2
  git merge --abort
  git switch -
  git branch -D "$branch"
  exit 4
fi

cat <<EOF
Upstream changes are staged on branch: $branch
No upstream Skill or script was executed, committed or pushed.

Required next steps:
  1. Review: git diff --cached --stat && git diff --cached
  2. Review every changed Skill script and lifecycle script before execution.
  3. Run the original upstream validation commands and the portfolio scanner.
  4. Commit and push only after review, then open a draft PR.
  5. Abort safely with: git merge --abort
EOF
