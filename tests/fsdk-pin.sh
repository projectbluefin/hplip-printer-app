#!/usr/bin/env bash
set -euo pipefail

# Offline checks of scripts/fsdk-pin.sh against a local fsdk-containers
# stand-in: it must accept any freedesktop-sdk-<version>-<n>-g<commit> ref
# (publishing once accepted only -0-g) and fail on anything else.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
remote="$tmp/fsdk-containers"
git init -q "$remote"
git -C "$remote" config uploadpack.allowAnySHA1InWant true
sha="0123456789abcdef0123456789abcdef01234567"

# commit <freedesktop-sdk.bst contents, empty to omit the file>
commit() {
  git -C "$remote" rm -q -r --ignore-unmatch elements >/dev/null
  if [[ -n "$1" ]]; then
    mkdir -p "$remote/elements"
    printf '%s\n' "$1" > "$remote/elements/freedesktop-sdk.bst"
    git -C "$remote" add elements
  fi
  git -C "$remote" -c user.name=test -c user.email=test@example.invalid \
    commit -q --allow-empty -m test
  git -C "$remote" rev-parse HEAD
}
bst() { printf 'kind: junction\nsources:\n- kind: git_repo\n  url: gitlab:freedesktop-sdk/freedesktop-sdk.git\n  ref: %s\n' "$1"; }
pin() { bash "$root/scripts/fsdk-pin.sh" "$1" "$remote"; }
reject() {
  if pin "$1" 2>/dev/null; then
    echo "fsdk-pin.sh accepted $2" >&2; exit 1
  fi
}

[[ "$(pin "$(commit "$(bst "freedesktop-sdk-25.08.4-0-g$sha")")")" == "25.08.4 $sha" ]]
[[ "$(pin "$(commit "$(bst "freedesktop-sdk-26.08.4-3-g$sha")")")" == "26.08.4 $sha" ]]
reject "$(commit "$(bst "freedesktop-sdk-25.08.4")")" 'a ref without a commit'
reject "$(commit "$(bst "$sha")")" 'a bare commit ref'
reject "$(commit '')" 'a commit with no elements/freedesktop-sdk.bst'
reject "$(printf '%040d' 0)" 'a commit the remote does not have'
echo 'OK: fsdk-pin.sh'
