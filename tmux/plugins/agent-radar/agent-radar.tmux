#!/usr/bin/env bash

set -euo pipefail

CURRENT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ENGINE=$CURRENT_DIR/bin/agent-radar

option() {
  local name=$1 fallback=$2 value
  value=$(tmux show-option -gqv "$name")
  printf '%s' "${value:-$fallback}"
}

shell_quote() {
  printf '%q' "$1"
}

set_default() {
  local name=$1 value=$2
  [ -n "$(tmux show-option -gqv "$name")" ] || tmux set-option -gq "$name" "$value"
}

set_default @agent-radar-popup-key 'M-c'
set_default @agent-radar-status 'on'
set_default @agent-radar-done-ttl '3'
set_default @agent-radar-cache-ttl '2'
set_default @agent-radar-state-dir "${XDG_STATE_HOME:-$HOME/.local/state}/agent-radar"
set_default @agent-radar-color-awaiting '#f7768e'
set_default @agent-radar-color-working '#e0af68'
set_default @agent-radar-color-done '#3fb950'
set_default @agent-radar-color-idle '#9ece6a'
set_default @agent-radar-color-accent '#7dcfff'
set_default @agent-radar-color-muted '#565f89'
set_default @agent-radar-color-dim '#414868'
set_default @agent-radar-color-pill-bg '#24283b'
set_default @agent-radar-color-status-bg '#050505'

engine_env="env"
engine_env="$engine_env AGENT_RADAR_STATE_DIR=$(shell_quote "$(option @agent-radar-state-dir "${XDG_STATE_HOME:-$HOME/.local/state}/agent-radar")")"
engine_env="$engine_env AGENT_RADAR_CACHE_TTL=$(shell_quote "$(option @agent-radar-cache-ttl 2)")"
engine_env="$engine_env AGENT_RADAR_ON_CHANGE=$(shell_quote "$(option @agent-radar-on-change '')")"
engine_env="$engine_env AGENT_RADAR_COLOR_AWAITING=$(shell_quote "$(option @agent-radar-color-awaiting '#f7768e')")"
engine_env="$engine_env AGENT_RADAR_COLOR_WORKING=$(shell_quote "$(option @agent-radar-color-working '#e0af68')")"
engine_env="$engine_env AGENT_RADAR_COLOR_DONE=$(shell_quote "$(option @agent-radar-color-done '#3fb950')")"
engine_env="$engine_env AGENT_RADAR_COLOR_IDLE=$(shell_quote "$(option @agent-radar-color-idle '#9ece6a')")"
engine_env="$engine_env AGENT_RADAR_COLOR_ACCENT=$(shell_quote "$(option @agent-radar-color-accent '#7dcfff')")"
engine_env="$engine_env AGENT_RADAR_COLOR_MUTED=$(shell_quote "$(option @agent-radar-color-muted '#565f89')")"
engine_env="$engine_env AGENT_RADAR_COLOR_DIM=$(shell_quote "$(option @agent-radar-color-dim '#414868')")"
engine_env="$engine_env AGENT_RADAR_COLOR_PILL_BG=$(shell_quote "$(option @agent-radar-color-pill-bg '#24283b')")"
engine_env="$engine_env AGENT_RADAR_COLOR_STATUS_BG=$(shell_quote "$(option @agent-radar-color-status-bg '#050505')")"
engine_command="$engine_env $(shell_quote "$ENGINE")"
tmux set-option -gq @agent-radar-runtime-command "$engine_command"

case "${1:-}" in
  --refresh)
    exec /bin/sh -c "$engine_command --refresh --notify"
    ;;
  --ack-pane)
    [ $# -eq 2 ] || exit 1
    exec /bin/sh -c "$engine_command --ack-pane $(shell_quote "$2")"
    ;;
esac

popup_key=$(option @agent-radar-popup-key 'M-c')
tmux bind-key -n "$popup_key" display-popup -B -E -w 80% -h 80% "$engine_command"

ack_command="$(shell_quote "$CURRENT_DIR/agent-radar.tmux") --ack-pane #{pane_id}"
ack_hook="run-shell -b $(shell_quote "$ack_command")"
tmux set-hook -g 'after-select-pane[90]' "$ack_hook"
tmux set-hook -g 'after-select-window[90]' "$ack_hook"
tmux set-hook -g 'client-session-changed[90]' "$ack_hook"
tmux set-hook -g 'pane-focus-in[90]' "$ack_hook"

fragment="#($engine_command --tmux-status-cached #{q:session_name})"
status_right=$(tmux show-option -gqv status-right)
previous_fragment=$(tmux show-option -gqv @agent-radar-fragment)
if [ -n "$previous_fragment" ]; then
  case "$status_right" in
    *"$previous_fragment") status_right=${status_right%"$previous_fragment"} ;;
  esac
fi
case "$status_right" in
  *"$fragment") status_right=${status_right%"$fragment"} ;;
esac
tmux set-option -gq @agent-radar-fragment "$fragment"

if [ "$(option @agent-radar-status 'on')" = on ]; then
  tmux set-option -g status-right "$status_right$fragment"
else
  tmux set-option -g status-right "$status_right"
fi
