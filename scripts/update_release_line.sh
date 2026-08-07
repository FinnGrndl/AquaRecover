#!/usr/bin/env bash
set -euo pipefail

main_ref="${1:-origin/main}"
release_branch="$(git branch --show-current)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release worktree must be clean before creating a snapshot." >&2
  exit 1
fi

git rev-parse --verify "$main_ref^{commit}" >/dev/null
source_sha="$(git rev-parse "$main_ref^{commit}")"
version_with_build="$(git show "$source_sha:pubspec.yaml" | awk '$1 == "version:" { print $2; exit }')"
version="${version_with_build%%+*}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version in $main_ref: $version_with_build" >&2
  exit 1
fi

release_major="${version%%.*}"
expected_branch="release/$release_major"
if [[ "$release_branch" != "$expected_branch" ]]; then
  echo "Run this script on $expected_branch, not $release_branch." >&2
  exit 1
fi

previous_source="$({
  git show -s --format=%B HEAD |
    sed -nE 's/^Release-Source: ([0-9a-f]{40})$/\1/p'
} | tail -n 1)"

if [[ -z "$previous_source" ]]; then
  previous_source="$({
    git show -s --format=%B HEAD |
      sed -nE 's/^\(cherry picked from commit ([0-9a-f]{40})\)$/\1/p'
  } | tail -n 1)"
fi

if [[ -z "$previous_source" ]]; then
  seed_tag="$(git tag --sort=-version:refname --points-at HEAD --list "v$release_major.*" | head -n 1)"
  if [[ -z "$seed_tag" ]]; then
    echo "Release line has neither a source marker nor a v$release_major.x tag at HEAD." >&2
    exit 1
  fi
  previous_source="$(git rev-list -n 1 "$seed_tag")"
fi

if ! git merge-base --is-ancestor "$previous_source" "$source_sha"; then
  echo "$previous_source is not an ancestor of $source_sha." >&2
  exit 1
fi

release_tree="$(git rev-parse "HEAD^{tree}")"
previous_tree="$(git rev-parse "$previous_source^{tree}")"
if [[ "$release_tree" != "$previous_tree" ]]; then
  echo "Current release tree differs from its recorded source $previous_source." >&2
  exit 1
fi

tag="v$version"
if git show-ref --verify --quiet "refs/tags/$tag"; then
  tagged_source="$(git rev-list -n 1 "$tag")"
  if [[ "$tagged_source" != "$source_sha" ]]; then
    echo "$tag already identifies $tagged_source; wait for main to prepare a newer version." >&2
    exit 1
  fi
fi

if [[ "$previous_source" == "$source_sha" ]]; then
  scripts/verify_release_snapshot.sh HEAD "$main_ref" >/dev/null
  echo "$expected_branch already matches $source_sha."
  exit 0
fi

start_head="$(git rev-parse HEAD)"
if git diff --quiet HEAD "$source_sha"; then
  echo "$source_sha has no releasable tree changes beyond $start_head." >&2
  exit 1
fi

git diff --binary --full-index HEAD "$source_sha" | git apply --index --binary

staged_tree="$(git write-tree)"
source_tree="$(git rev-parse "$source_sha^{tree}")"
if [[ "$staged_tree" != "$source_tree" ]]; then
  echo "Staged release snapshot differs from $source_sha." >&2
  exit 1
fi

git commit \
  -m "chore(release): snapshot v$version" \
  -m "Release-Source: $source_sha"

if [[ "$(git rev-list --count "$start_head..HEAD")" != "1" ]]; then
  echo "Release update must create exactly one commit." >&2
  exit 1
fi

verified_source="$(scripts/verify_release_snapshot.sh HEAD "$main_ref")"
if [[ "$verified_source" != "$source_sha" ]]; then
  echo "Release line resolved to $verified_source instead of $source_sha." >&2
  exit 1
fi

printf '%s now matches %s (%s) in one snapshot commit.\n' \
  "$expected_branch" "$source_sha" "$version_with_build"
