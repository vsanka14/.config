#!/usr/bin/env bash

set -euo pipefail

plugin_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

cat >"$temp_dir/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state=$FAKE_TMUX_STATE
command=$1
shift

case "$command" in
  show-option)
    while [ $# -gt 1 ]; do shift; done
    name=$1
    key=$(printf '%s' "$name" | tr -c '[:alnum:]_-' '_')
    [ -f "$state/$key" ] && cat "$state/$key"
    exit 0
    ;;
  set-option)
    while [ $# -gt 0 ] && [ "${1#-}" != "$1" ]; do shift; done
    name=$1
    value=${2:-}
    key=$(printf '%s' "$name" | tr -c '[:alnum:]_-' '_')
    printf '%s' "$value" >"$state/$key"
    ;;
  bind-key)
    printf '%s\n' "$*" >>"$state/bindings"
    ;;
  set-hook)
    printf '%s\n' "$*" >>"$state/hooks"
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$temp_dir/tmux"
mkdir -p "$temp_dir/state"

run_entrypoint() {
  FAKE_TMUX_STATE="$temp_dir/state" PATH="$temp_dir:$PATH" \
    bash "$plugin_dir/agent-radar.tmux"
}

run_entrypoint
run_entrypoint

status_file=$temp_dir/state/status-right
[ -f "$status_file" ] || {
  printf 'not ok - status-right was not configured\n' >&2
  exit 1
}

count=$(grep -o 'agent-radar --tmux-status-cached' "$status_file" | wc -l | tr -d ' ')
[ "$count" = 1 ] || {
  printf 'not ok - status fragment was injected %s times\n' "$count" >&2
  exit 1
}

grep -Fq -- '-n M-c display-popup' "$temp_dir/state/bindings" || {
  printf 'not ok - popup binding was not configured\n' >&2
  exit 1
}

for hook in after-select-pane after-select-window client-session-changed pane-focus-in; do
  grep -Fq -- "$hook" "$temp_dir/state/hooks" &&
    grep -Fq -- '--ack-pane\ #\{pane_id\}' "$temp_dir/state/hooks" || {
      printf 'not ok - %s acknowledgement hook was not configured\n' "$hook" >&2
      exit 1
    }
done

for hook in session-created session-closed session-renamed; do
  grep -F -- "$hook" "$temp_dir/state/hooks" |
    grep -Fq -- 'agent-radar.tmux\ --refresh' || {
      printf 'not ok - %s refresh hook was not configured\n' "$hook" >&2
      exit 1
    }
done

if grep -Eq 'RECONCILE|STALE_SECONDS|STATUS_TTL|AWAITING_IDLE_GRACE' \
  "$temp_dir/state/_agent-radar-runtime-command"; then
  printf 'not ok - removed reconciliation settings remain in the runtime\n' >&2
  exit 1
fi

printf 'ok - agent radar tmux entrypoint\n'
