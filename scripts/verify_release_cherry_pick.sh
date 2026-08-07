#!/usr/bin/env bash
set -euo pipefail

release_commit="${1:-HEAD}"
main_ref="${2:-origin/main}"

git rev-parse --verify "$release_commit^{commit}" >/dev/null
git rev-parse --verify "$main_ref^{commit}" >/dev/null

parent_count="$(git rev-list --parents -n 1 "$release_commit" | awk '{print NF - 1}')"
if [[ "$parent_count" != "1" ]]; then
  echo "Release trigger must be a non-merge cherry-pick." >&2
  exit 1
fi

source_sha="$({
  git show -s --format=%B "$release_commit" |
    sed -nE 's/^\(cherry picked from commit ([0-9a-f]{40})\)$/\1/p'
} | tail -n 1)"
if [[ -z "$source_sha" ]]; then
  echo "Release commit is missing the marker created by git cherry-pick -x." >&2
  exit 1
fi

git rev-parse --verify "$source_sha^{commit}" >/dev/null
if ! git merge-base --is-ancestor "$source_sha" "$main_ref"; then
  echo "Cherry-picked source $source_sha is not part of $main_ref." >&2
  exit 1
fi

release_tree="$(git rev-parse "$release_commit^{tree}")"
source_tree="$(git rev-parse "$source_sha^{tree}")"
if [[ "$release_tree" != "$source_tree" ]]; then
  echo "Release tree differs from the tested source commit $source_sha." >&2
  echo "Update release/<major> by cherry-picking every new main commit with -x, then push once." >&2
  exit 1
fi

printf '%s\n' "$source_sha"
