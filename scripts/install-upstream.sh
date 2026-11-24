#!/usr/bin/env bash
# Upstream install of the Antigravity CLI runtime plugin.
#
# Installs the release pinned in `compat/RELEASE` into `$UPSTREAM_BIN/agy`
# from the exact archive URL and SHA-512 checksum recorded in
# `compat/compatibility-lock.json` for this platform (`linux_x86_64` or
# `darwin_arm64`).
#
# The CI smoke step runs this script with the repository root as the working
# directory and `UPSTREAM_BIN` set to an absolute directory; the local smoke
# check does the same (see "Local checks" in README.md).
set -euo pipefail

if [ -z "${UPSTREAM_BIN:-}" ]; then
  echo "install-upstream.sh: UPSTREAM_BIN is unset" >&2
  exit 1
fi
mkdir -p "$UPSTREAM_BIN"

version="$(sed -e 's/#.*//' compat/RELEASE | grep -v '^[[:space:]]*$' | tail -n 1 || true)"
if [ -z "$version" ]; then
  echo "install-upstream.sh: no release in compat/RELEASE" >&2
  exit 1
fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "install-upstream.sh: invalid release '$version' in compat/RELEASE (want MAJOR.MINOR.PATCH)" >&2
  exit 1
fi

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) platform="linux_x86_64" ;;
  Darwin:arm64|Darwin:aarch64) platform="darwin_arm64" ;;
  *)
    echo "install-upstream.sh: unsupported platform $(uname -s)/$(uname -m)" >&2
    exit 1
    ;;
esac

lock="compat/compatibility-lock.json"
if [ ! -f "$lock" ]; then
  echo "install-upstream.sh: missing lock file '$lock'" >&2
  exit 1
fi

read -r lock_release url sha512 < <(
  python3 -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
up = doc["upstream"]
arch = up["archives"][sys.argv[2]]
print(up["release"], arch["url"], arch["sha512"])
' "$lock" "$platform"
)

if [ "$lock_release" != "$version" ]; then
  echo "install-upstream.sh: compat/RELEASE ($version) != lock release ($lock_release)" >&2
  exit 1
fi

tmpdir="$(mktemp -d "$UPSTREAM_BIN/.install-agy.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/agy.tar.gz"
curl -fsSL -o "$archive" "$url"

if [ "$(uname -s)" = "Darwin" ]; then
  actual_sha512="$(shasum -a 512 "$archive" | cut -d' ' -f1)"
else
  actual_sha512="$(sha512sum "$archive" | cut -d' ' -f1)"
fi

if [ "$actual_sha512" != "$sha512" ]; then
  echo "install-upstream.sh: SHA-512 mismatch for $url (got $actual_sha512, want $sha512)" >&2
  exit 1
fi

tar -xzf "$archive" -C "$tmpdir" antigravity
mv "$tmpdir/antigravity" "$UPSTREAM_BIN/agy"
chmod +x "$UPSTREAM_BIN/agy"

probed="$("$UPSTREAM_BIN/agy" --version)"
if [ "$probed" != "$version" ]; then
  echo "install-upstream.sh: installed agy reported '$probed', want '$version'" >&2
  exit 1
fi
