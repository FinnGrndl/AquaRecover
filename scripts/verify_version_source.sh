#!/usr/bin/env bash
set -euo pipefail

source_commit="${1:-HEAD}"
main_ref="${2:-origin/main}"

git rev-parse --verify "$source_commit^{commit}" >/dev/null
git rev-parse --verify "$main_ref^{commit}" >/dev/null

if ! git merge-base --is-ancestor "$source_commit" "$main_ref"; then
  echo "Version source $source_commit is not part of $main_ref." >&2
  exit 1
fi

parent_count="$(git rev-list --parents -n 1 "$source_commit" | awk '{print NF - 1}')"
if [[ "$parent_count" != "1" ]]; then
  echo "Version source must be a single-parent preparation commit." >&2
  exit 1
fi

subject="$(git show -s --format=%s "$source_commit")"
if [[ ! "$subject" =~ ^chore\(release\):\ prepare\ v(.+)$ ]]; then
  echo "Version source must be a chore(release): prepare commit." >&2
  exit 1
fi
subject_version="${BASH_REMATCH[1]}"
version_with_build="$(git show "$source_commit:pubspec.yaml" | awk '$1 == "version:" { print $2; exit }')"
project_version="${version_with_build%%+*}"
if [[ "$project_version" != "$subject_version" ]]; then
  echo "Version source subject and pubspec.yaml disagree." >&2
  exit 1
fi

allowed_paths='^(CHANGELOG\.md|README\.md|THIRD_PARTY_NOTICES\.md|pubspec\.yaml|lib/core/app_version\.dart|\.github/ISSUE_TEMPLATE/bug_report\.yml)$'
unexpected="$({
  git diff-tree --no-commit-id --name-only -r "$source_commit^" "$source_commit" |
    grep -Ev "$allowed_paths" || true
})"
if [[ -n "$unexpected" ]]; then
  echo "Version preparation changed files outside the generated allowlist:" >&2
  printf '%s\n' "$unexpected" >&2
  exit 1
fi

git rev-parse "$source_commit^"
