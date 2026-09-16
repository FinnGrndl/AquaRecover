#!/usr/bin/env bash
set -euo pipefail

source_commit="${1:-HEAD}"
main_ref="${2:-origin/main}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git rev-parse --verify "$source_commit^{commit}" >/dev/null
git rev-parse --verify "$main_ref^{commit}" >/dev/null
source_sha="$(git rev-parse "$source_commit^{commit}")"

if ! git merge-base --is-ancestor "$source_sha" "$main_ref"; then
  echo "Release source $source_sha is not part of $main_ref." >&2
  exit 1
fi

version_with_build="$(git show "$source_sha:pubspec.yaml" | awk '$1 == "version:" { print $2; exit }')"
version="${version_with_build%%+*}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version in release source: $version_with_build" >&2
  exit 1
fi

prepare_subject="chore(release): prepare v$version"
prepare_commit="$({
  git log --first-parent --format='%H%x09%s' "$source_sha" |
    awk -F '\t' -v subject="$prepare_subject" '
      $2 == subject && commit == "" { commit = $1 }
      END { print commit }
    '
})"
if [[ -z "$prepare_commit" ]]; then
  echo "Release source has no generated $prepare_subject commit." >&2
  exit 1
fi
"$script_dir/verify_version_source.sh" "$prepare_commit" "$main_ref" >/dev/null

source_subject="$(git show -s --format=%s "$source_sha")"
source_parent_count="$(git rev-list --parents -n 1 "$source_sha" | awk '{print NF - 1}')"
if [[ "$source_sha" == "$prepare_commit" ]]; then
  tested_merge="$(git rev-parse "$source_sha^")"
elif [[ "$source_parent_count" == "2" ]]; then
  tested_merge="$source_sha"
else
  echo "Release source must be a generated version commit or a tested pull-request merge." >&2
  echo "Found $source_subject with $source_parent_count parent(s)." >&2
  exit 1
fi

tested_parent_count="$(git rev-list --parents -n 1 "$tested_merge" | awk '{print NF - 1}')"
if [[ "$tested_parent_count" != "2" ]]; then
  echo "Validated source $tested_merge is not a pull-request merge commit." >&2
  exit 1
fi

printf '%s\n' "$tested_merge"
