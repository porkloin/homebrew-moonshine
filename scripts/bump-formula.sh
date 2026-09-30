#!/usr/bin/env bash
# Point Formula/moonshine.rb at the latest hgaiser/moonshine release (or TAG).
#
#   scripts/bump-formula.sh [TAG]
#
# Rewrites the formula's url + sha256 in place. Exits 0 without touching
# anything when the formula is already current.
#
# Refuses to bump (exit 3) when the release tarball's file list differs from
# scripts/release-files.txt: a new unit/rules/sysusers file usually needs a
# formula or setup-script change (0.16 added the moonshine group, and without
# it the unit won't start), so that has to be looked at by a human. After
# updating the formula for the new layout, rerun with --accept-layout to
# refresh the list.
#
# Writes version=/changed= to $GITHUB_OUTPUT when run in Actions.
set -euo pipefail

REPO="hgaiser/moonshine"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORMULA="$ROOT/Formula/moonshine.rb"
FILES_LIST="$ROOT/scripts/release-files.txt"

accept_layout=0
tag=""
for arg in "$@"; do
  case "$arg" in
    --accept-layout) accept_layout=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) tag="$arg" ;;
  esac
done

output() { [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "$1" >> "$GITHUB_OUTPUT"; return 0; }

if [[ -z "$tag" ]]; then
  tag="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
fi
version="${tag#v}"
current="$(sed -nE 's|.*/releases/download/v([^/]+)/.*|\1|p' "$FORMULA")"
output "version=$version"

if [[ "$version" == "$current" && $accept_layout -eq 0 ]]; then
  echo "Formula already at $current"
  output "changed=false"
  exit 0
fi

asset="moonshine-v${version}-linux-amd64.tar.zst"
url="https://github.com/$REPO/releases/download/v${version}/${asset}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "Downloading $url"
curl -fsSL --retry 3 -o "$tmp/$asset" "$url"
sha="$(sha256sum "$tmp/$asset" | cut -d' ' -f1)"

tar --zstd -tf "$tmp/$asset" | grep -v '/$' | sed 's|^[^/]*/||' | LC_ALL=C sort > "$tmp/files.txt"
if ! diff -u "$FILES_LIST" "$tmp/files.txt" > "$tmp/layout.diff"; then
  if [[ $accept_layout -eq 1 ]]; then
    cp "$tmp/files.txt" "$FILES_LIST"
  else
    echo "Release $tag changed the tarball layout (- was, + now):" >&2
    cat "$tmp/layout.diff" >&2
    echo "Update the formula/setup script for it, then: scripts/bump-formula.sh $tag --accept-layout" >&2
    output "changed=false"
    exit 3
  fi
fi

sed -i -E \
  -e "s|^(  url \")[^\"]+(\")|\1${url}\2|" \
  -e "s|^(  sha256 \")[^\"]+(\")|\1${sha}\2|" \
  "$FORMULA"

echo "Formula: $current -> $version ($sha)"
output "changed=true"
