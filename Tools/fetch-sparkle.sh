#!/bin/bash
set -euo pipefail
project="$(cd "$(dirname "$0")/.." && pwd)"
cache="$project/.build/downloads"
archive="$cache/Sparkle-2.10.1.tar.xz"
expected="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
mkdir -p "$cache"
temporary=""
trap 'if [[ -n "$temporary" && -f "$temporary" ]]; then rm "$temporary"; fi' EXIT
if [[ ! -f "$archive" ]]; then
  temporary="$(mktemp "$cache/.sparkle.XXXXXX")"
  curl --proto '=https' --tlsv1.2 --fail --location --retry 2 --silent --show-error \
    'https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz' -o "$temporary"
  actual="$(shasum -a 256 "$temporary" | cut -d ' ' -f 1)"
  [[ "$actual" == "$expected" ]] || { printf 'Sparkle checksum mismatch.\n' >&2; exit 1; }
  mv "$temporary" "$archive"
  temporary=""
fi
actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
[[ "$actual" == "$expected" ]] || { printf 'Cached Sparkle checksum mismatch. Remove %s and retry.\n' "$archive" >&2; exit 1; }
printf '%s\n' "$archive"
