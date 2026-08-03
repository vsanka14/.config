#!/usr/bin/env bash

agent_radar_on_change_command() {
  local command=${AGENT_RADAR_ON_CHANGE:-}
  if [ -z "$command" ] && command -v "${TMUX_BIN:-tmux}" >/dev/null 2>&1; then
    command=$("${TMUX_BIN:-tmux}" show-option -gqv @agent-radar-on-change 2>/dev/null) || command=
  fi
  printf '%s' "$command"
}

remove_agent_radar_popup() {
  local registration=$1 socket=$2 socket_dir
  case "$socket" in
    */.agent-radar.*/fzf.sock)
      socket_dir=${socket%/*}
      rm -f -- "$socket"
      rmdir "$socket_dir" 2>/dev/null || true
      ;;
  esac
  rm -f -- "$registration"
}

refresh_agent_radar_popups() {
  local registry engine registration socket owner_pid action
  registry=$(agent_radar_state_dir)/.popups
  [ -d "$registry" ] && [ ! -L "$registry" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  engine=${AGENT_RADAR_ENGINE_BIN:-}
  [ -x "$engine" ] || return 0
  action="reload($(printf '%q' "$engine") --list)"

  for registration in "$registry"/*; do
    [ -f "$registration" ] && [ ! -L "$registration" ] || continue
    IFS= read -r socket <"$registration" || socket=
    owner_pid=$(sed -n '2p' "$registration" 2>/dev/null || true)
    case "$owner_pid" in
      *[!0-9]*|'')
        remove_agent_radar_popup "$registration" "$socket"
        continue
        ;;
      *)
        if ! kill -0 "$owner_pid" 2>/dev/null; then
          remove_agent_radar_popup "$registration" "$socket"
          continue
        fi
        ;;
    esac
    [ -S "$socket" ] || {
      remove_agent_radar_popup "$registration" "$socket"
      continue
    }
    curl -fsS --unix-socket "$socket" http://localhost \
      --connect-timeout 0.1 --max-time 0.5 \
      --data-binary "$action" >/dev/null 2>&1 || true
  done
}

emit_agent_radar_change() {
  [ "${AGENT_RADAR_NOTIFY:-1}" != 0 ] || return 0
  refresh_agent_radar_popups
  local command
  command=$(agent_radar_on_change_command)
  [ -n "$command" ] || return 0
  ( /bin/sh -c "$command" >/dev/null 2>&1 ) &
  disown 2>/dev/null || true
}
