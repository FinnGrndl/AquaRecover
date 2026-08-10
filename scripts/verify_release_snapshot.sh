#!/usr/bin/env bash
set -euo pipefail

release_commit="${1:-HEAD}"
main_ref="${2:-origin/main}"

git rev-parse --verify "$release_commit^{commit}" >/dev/null
git rev-parse --verify "$main_ref^{commit}" >/dev/null

parent_count="$(git rev-list --parents -n 1 "$release_commit" | awk '{print NF - 1}')"
if [[ "$parent_count" != "1" ]]; then
  echo "Release trigger must be a single-parent snapshot commit." >&2
  exit 1
fi

commit_message="$(git show -s --format=%B "$release_commit")"
source_sha="$({
  printf '%s\n' "$commit_message" |
    sed -nE 's/^Release-Source: ([0-9a-f]{40})$/\1/p'
} | tail -n 1)"

if [[ -n "$source_sha" ]]; then
  subject="$(git show -s --format=%s "$release_commit")"
  if [[ ! "$subject" =~ ^chore\(release\):\ snapshot\ v ]]; then
    echo "Release snapshot subject must start with 'chore(release): snapshot v'." >&2
    exit 1
  fi
else
  # Accept the existing release/1 history once so the first snapshot can migrate
  # from the former per-commit cherry-pick format without rewriting the branch.
  source_sha="$({
    printf '%s\n' "$commit_message" |
      sed -nE 's/^\(cherry picked from commit ([0-9a-f]{40})\)$/\1/p'
  } | tail -n 1)"
fi

if [[ -z "$source_sha" ]]; then
  echo "Release commit is missing a Release-Source trailer." >&2
  exit 1
fi

git rev-parse --verify "$source_sha^{commit}" >/dev/null
if ! git merge-base --is-ancestor "$source_sha" "$main_ref"; then
  echo "Release source $source_sha is not part of $main_ref." >&2
  exit 1
fi

release_tree="$(git rev-parse "$release_commit^{tree}")"
source_tree="$(git rev-parse "$source_sha^{tree}")"
if [[ "$release_tree" != "$source_tree" ]]; then
  echo "Release tree differs from the tested source commit $source_sha." >&2
  echo "Create one snapshot commit from the complete tested main tree." >&2
  exit 1
fi

printf '%s\n' "$source_sha"
