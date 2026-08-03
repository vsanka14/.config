#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if grep -R -n -E '(\$HOME/\.config|~/\.config|sketchybar|bin/tmux-agent-(engine|status))' \
  "$plugin_dir/agent-radar.tmux" \
  "$plugin_dir/bin" \
  "$plugin_dir/lib" \
  "$plugin_dir/agents"; then
  printf 'not ok - plugin boundary violation\n' >&2
  exit 1
fi

cp -R "$plugin_dir" "$temp_dir/agent-radar"
bash "$temp_dir/agent-radar/tests/engine-test.sh" >/dev/null

printf 'ok - agent radar plugin boundary\n'
