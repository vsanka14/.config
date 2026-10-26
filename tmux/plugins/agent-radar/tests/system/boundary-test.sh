#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
candidate=${AGENT_RADAR_BIN:-$plugin_dir/bin/agent-radar}
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

if grep -R -n -E '(\$HOME/\.config|~/\.config|sketchybar|bin/tmux-agent-(engine|status))' \
  "$plugin_dir/agent-radar.tmux" \
  "$plugin_dir/src"; then
  printf 'not ok - plugin boundary violation\n' >&2
  exit 1
fi

# Copy the plugin into isolation, excluding the Rust build directory: it is
# ~300MB / 14k files, would slow this copy to minutes, and triggers a large
# antivirus scan burst. Install the validated candidate into the relocated
# plugin so the smoke test exercises the same single-binary layout as runtime.
copy_dir=$temp_dir/agent-radar
mkdir -p "$copy_dir"
tar -C "$plugin_dir" \
  --exclude './target' \
  --exclude './bin/agent-radar' \
  --exclude './bin/agent-radar-hook' \
  -cf - . |
  tar -C "$copy_dir" -xf -
install -m 755 "$candidate" "$copy_dir/bin/agent-radar"

# Relocation smoke test: prove the plugin renders from a fresh location with no
# dependency on its original path. The full engine-test suite already ran
# directly against the real tree earlier in dev-check, so re-running all of its
# assertions here only duplicated ~8s of work; a single render is enough to
# catch a hardcoded original-path regression.
fixture_dir=$temp_dir/fixture
state_dir=$fixture_dir/state
mkdir -p "$state_dir"

cat >"$fixture_dir/panes" <<'EOF'
%1	alpha	1	1	100	Copilot Session - GitHub Copilot
%2	beta	1	1	200	Copilot Session - GitHub Copilot
EOF

cat >"$fixture_dir/processes" <<'EOF'
100 1 bash
101 100 copilot
200 1 bash
201 200 copilot
EOF

cat >"$fixture_dir/fake-tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  list-panes) cat "$FIXTURE_DIR/panes" ;;
  list-sessions)
    fmt=
    while [ $# -gt 0 ]; do
      if [ "$1" = -F ]; then fmt=$2; break; fi
      shift
    done
    case "$fmt" in
      *session_created*) printf '100\talpha\n200\tbeta\n' ;;
      *) printf 'alpha\nbeta\n' ;;
    esac
    ;;
  switch-client|select-pane|run-shell|refresh-client) exit 0 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$fixture_dir/fake-tmux"

jq -n '{pane_id:"%1",session_id:"test",status:"awaiting",event:"test",updated_at:"test",updated_epoch:2000000000}' \
  >"$state_dir/1.json"
jq -n '{pane_id:"%2",session_id:"test",status:"working",event:"test",updated_at:"test",updated_epoch:2000000000}' \
  >"$state_dir/2.json"

render=$(
  FIXTURE_DIR="$fixture_dir" \
    TMUX_AGENT_ENGINE_TMUX_BIN="$fixture_dir/fake-tmux" \
    TMUX_AGENT_ENGINE_PS_FILE="$fixture_dir/processes" \
    TMUX_AGENT_ENGINE_STATE_DIR="$state_dir" \
    TMUX_AGENT_ENGINE_NOW=2000000000 \
    "$copy_dir/bin/agent-radar" --tmux-status alpha
)

if [ -z "$render" ]; then
  printf 'not ok - relocated plugin produced no status output\n' >&2
  exit 1
fi

case "$render" in
  *"$plugin_dir"*)
    printf 'not ok - relocated render leaked original plugin path\n' >&2
    exit 1
    ;;
esac

printf 'ok - agent radar plugin boundary\n'
