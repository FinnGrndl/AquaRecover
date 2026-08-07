#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_repo="$(mktemp -d "${TMPDIR:-/tmp}/aquarecover-release-snapshot.XXXXXX")"
trap 'rm -rf "$test_repo"' EXIT

git init -q -b main "$test_repo"
cd "$test_repo"
git config user.name "Release Test"
git config user.email "release-test@example.invalid"

mkdir scripts
cp "$script_dir/update_release_line.sh" scripts/
cp "$script_dir/verify_release_snapshot.sh" scripts/
chmod +x scripts/*.sh

printf 'version: 1.1.0+8\n' >pubspec.yaml
printf 'baseline\n' >app.txt
git add .
git commit -q -m "chore: seed release test"

printf 'version: 1.1.1+9\n' >pubspec.yaml
printf 'released\n' >app.txt
git add pubspec.yaml app.txt
git commit -q -m "chore(release): prepare v1.1.1"
old_source="$(git rev-parse HEAD)"
git tag v1.1.1

git switch -q -c release/1 HEAD^
git cherry-pick -x "$old_source" >/dev/null
legacy_release_head="$(git rev-parse HEAD)"

git switch -q main
printf 'fixed\n' >app.txt
git add app.txt
git commit -q -m "fix: test snapshot update"
printf 'version: 1.1.2+10\n' >pubspec.yaml
git add pubspec.yaml
git commit -q -m "chore(release): prepare v1.1.2"
source_sha="$(git rev-parse HEAD)"

git switch -q release/1
scripts/update_release_line.sh main >/dev/null

if [[ "$(git rev-list --count "$legacy_release_head..HEAD")" != "1" ]]; then
  echo "Release update did not create exactly one snapshot commit." >&2
  exit 1
fi
if [[ "$(scripts/verify_release_snapshot.sh HEAD main)" != "$source_sha" ]]; then
  echo "Snapshot verifier did not return the tested main source." >&2
  exit 1
fi
if [[ "$(git rev-parse "HEAD^{tree}")" != "$(git rev-parse "$source_sha^{tree}")" ]]; then
  echo "Snapshot tree differs from the tested main tree." >&2
  exit 1
fi
if [[ "$(git show -s --format=%s HEAD)" != "chore(release): snapshot v1.1.2" ]]; then
  echo "Snapshot commit has the wrong subject." >&2
  exit 1
fi
if ! git show -s --format=%B HEAD | grep -Fxq "Release-Source: $source_sha"; then
  echo "Snapshot commit is missing its source trailer." >&2
  exit 1
fi

snapshot_head="$(git rev-parse HEAD)"
git tag v1.1.2 "$source_sha"
scripts/update_release_line.sh main >/dev/null
if [[ "$(git rev-parse HEAD)" != "$snapshot_head" ]]; then
  echo "An unchanged source created another release commit." >&2
  exit 1
fi

git switch -q main
printf 'pipeline-only change\n' >ci.txt
git add ci.txt
git commit -q -m "ci: test release guard"
git switch -q release/1
if scripts/update_release_line.sh main >/dev/null 2>&1; then
  echo "A changed source with an already released version was accepted." >&2
  exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$snapshot_head" ]]; then
  echo "Rejected release update changed the release branch." >&2
  exit 1
fi

echo "Release snapshot test passed."
