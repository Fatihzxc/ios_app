#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_commit="$(git -C "$repo_root" rev-parse HEAD)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
clone_root="$fixture/clone"

git clone --no-local --quiet "$repo_root" "$clone_root"
git -C "$clone_root" checkout --detach --quiet "$source_commit"

fingerprint_project() {
    python3 - "$clone_root/HealthTrackingApp.xcodeproj" <<'PY'
import hashlib
import sys
from pathlib import Path

project = Path(sys.argv[1])
if not project.is_dir():
    raise SystemExit(f"Generated project is missing: {project}")

digest = hashlib.sha256()
files = sorted(path for path in project.rglob("*") if path.is_file())
if not files:
    raise SystemExit(f"Generated project contains no files: {project}")
for path in files:
    relative = path.relative_to(project).as_posix().encode("utf-8")
    digest.update(relative)
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")
print(digest.hexdigest())
PY
}

(
    cd "$clone_root"
    ./scripts/bootstrap.sh
)
first_fingerprint="$(fingerprint_project)"

(
    cd "$clone_root"
    ./scripts/bootstrap.sh
)
second_fingerprint="$(fingerprint_project)"

if [[ "$first_fingerprint" != "$second_fingerprint" ]]; then
    echo "Bootstrap is not idempotent: project fingerprints differ." >&2
    echo "first:  $first_fingerprint" >&2
    echo "second: $second_fingerprint" >&2
    exit 1
fi

tracked_changes="$(git -C "$clone_root" status --short --untracked-files=no)"
if [[ -n "$tracked_changes" ]]; then
    echo "Bootstrap changed tracked files in a fresh clone:" >&2
    printf '%s\n' "$tracked_changes" >&2
    exit 1
fi

echo "Fresh-clone bootstrap idempotence passed for $source_commit."
echo "Generated project SHA-256: $second_fingerprint"
