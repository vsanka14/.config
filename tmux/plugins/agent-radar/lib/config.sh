#!/usr/bin/env bash

agent_radar_tmux_option() {
  local name=$1 fallback=$2 value=
  if command -v "${TMUX_BIN:-tmux}" >/dev/null 2>&1; then
    value=$("${TMUX_BIN:-tmux}" show-option -gqv "$name" 2>/dev/null) || value=
  fi
  printf '%s' "${value:-$fallback}"
}

agent_radar_state_dir() {
  if [ -n "${AGENT_RADAR_STATE_DIR:-}" ]; then
    printf '%s' "$AGENT_RADAR_STATE_DIR"
  elif [ -n "${TMUX_AGENT_ENGINE_STATE_DIR:-}" ]; then
    printf '%s' "$TMUX_AGENT_ENGINE_STATE_DIR"
  else
    printf '%s/agent-radar' "${XDG_STATE_HOME:-$HOME/.local/state}"
  fi
}

agent_radar_file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

agent_radar_shell_quote() {
  printf '%q' "$1"
}

agent_radar_runtime_command() {
  local engine=$1
  printf 'env AGENT_RADAR_STATE_DIR=%s' "$(agent_radar_shell_quote "$STATE_DIR")"
  printf ' AGENT_RADAR_TMUX_BIN=%s' "$(agent_radar_shell_quote "$TMUX_BIN")"
  printf ' AGENT_RADAR_CACHE_TTL=%s' "$(agent_radar_shell_quote "$CACHE_TTL")"
  printf ' AGENT_RADAR_ON_CHANGE=%s' "$(agent_radar_shell_quote "${AGENT_RADAR_ON_CHANGE:-}")"
  printf ' AGENT_RADAR_COLOR_AWAITING=%s' "$(agent_radar_shell_quote "$COLOR_AWAITING")"
  printf ' AGENT_RADAR_COLOR_WORKING=%s' "$(agent_radar_shell_quote "$COLOR_WORKING")"
  printf ' AGENT_RADAR_COLOR_DONE=%s' "$(agent_radar_shell_quote "$COLOR_DONE")"
  printf ' AGENT_RADAR_COLOR_IDLE=%s' "$(agent_radar_shell_quote "$COLOR_IDLE")"
  printf ' AGENT_RADAR_COLOR_ACCENT=%s' "$(agent_radar_shell_quote "$COLOR_ACCENT")"
  printf ' AGENT_RADAR_COLOR_MUTED=%s' "$(agent_radar_shell_quote "$COLOR_MUTED")"
  printf ' AGENT_RADAR_COLOR_DIM=%s' "$(agent_radar_shell_quote "$COLOR_DIM")"
  printf ' AGENT_RADAR_COLOR_PILL_BG=%s' "$(agent_radar_shell_quote "$COLOR_PILL_BG")"
  printf ' AGENT_RADAR_COLOR_STATUS_BG=%s %s' \
    "$(agent_radar_shell_quote "$COLOR_STATUS_BG")" \
    "$(agent_radar_shell_quote "$engine")"
}
