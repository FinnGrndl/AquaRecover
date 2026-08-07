#!/usr/bin/env bash
set -euo pipefail

main_ref="${1:-origin/main}"
release_branch="$(git branch --show-current)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Release worktree must be clean before cherry-picking." >&2
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
    sed -nE 's/^\(cherry picked from commit ([0-9a-f]{40})\)$/\1/p'
} | tail -n 1)"

if [[ -z "$previous_source" ]]; then
  seed_tag="$(git tag --sort=-version:refname --points-at HEAD --list "v$release_major.*" | head -n 1)"
  if [[ -z "$seed_tag" ]]; then
    echo "Release line has neither a cherry-pick marker nor a v$release_major.x tag at HEAD." >&2
    exit 1
  fi
  previous_source="$(git rev-list -n 1 "$seed_tag")"
fi

if ! git merge-base --is-ancestor "$previous_source" "$source_sha"; then
  echo "$previous_source is not an ancestor of $source_sha." >&2
  exit 1
fi

if [[ "$previous_source" == "$source_sha" ]]; then
  scripts/verify_release_cherry_pick.sh HEAD "$main_ref" >/dev/null
  echo "$expected_branch already matches $source_sha."
  exit 0
fi

commits=()
while IFS= read -r commit_sha; do
  commits+=("$commit_sha")
done < <(git rev-list --reverse --first-parent "$previous_source..$source_sha")
if [[ "${#commits[@]}" -eq 0 ]]; then
  echo "No commits found between $previous_source and $source_sha." >&2
  exit 1
fi

for commit_sha in "${commits[@]}"; do
  parent_count="$(git rev-list --parents -n 1 "$commit_sha" | awk '{ print NF - 1 }')"
  if [[ "$parent_count" != "1" ]]; then
    echo "Main commit $commit_sha is a merge commit; use squash merges on main." >&2
    exit 1
  fi
  git cherry-pick -x "$commit_sha"
done

verified_source="$(scripts/verify_release_cherry_pick.sh HEAD "$main_ref")"
if [[ "$verified_source" != "$source_sha" ]]; then
  echo "Release line resolved to $verified_source instead of $source_sha." >&2
  exit 1
fi

printf '%s now matches %s (%s).\n' "$expected_branch" "$source_sha" "$version_with_build"
