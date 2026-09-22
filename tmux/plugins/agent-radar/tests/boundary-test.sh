#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if grep -R -n -E '(\$HOME/\.config|~/\.config|sketchybar|bin/tmux-agent-(engine|status))' \
  "$plugin_dir/agent-radar.tmux" \
  "$plugin_dir/bin" \
  "$plugin_dir/src"; then
  printf 'not ok - plugin boundary violation\n' >&2
  exit 1
fi

# Copy the plugin into isolation, excluding the Rust build directory: it is
# ~300MB / 14k files, would slow this copy to minutes, and triggers a large
# antivirus scan burst. The isolated engine-test uses bin/agent-radar ->
# bin/agent-radar-rust, not target/.
mkdir -p "$temp_dir/agent-radar"
tar -C "$plugin_dir" --exclude './target' -cf - . \
  | tar -C "$temp_dir/agent-radar" -xf -
bash "$temp_dir/agent-radar/tests/engine-test.sh" >/dev/null

printf 'ok - agent radar plugin boundary\n'
