#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
install_dir="${1:-$HOME/Applications}"
destination="$install_dir/SongWave.app"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  printf 'Install the Xcode Command Line Tools with "xcode-select --install", then rerun this script.\n' >&2
  exit 1
fi

printf 'Building SongWave for %s…\n' "$(uname -m)"
"$project_dir/build.sh" "$destination"
printf 'Installed %s\n' "$destination"
printf 'Open it in Finder or run: open "%s"\n' "$destination"
