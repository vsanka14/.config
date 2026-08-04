#!/usr/bin/env bash

AGENT_RADAR_AGENT_NAME=copilot
AGENT_RADAR_PROCESS_BASENAME=copilot
AGENT_RADAR_TITLE_SUFFIX=' - GitHub Copilot'

agent_event_status() {
  case "$1" in
    sessionStart) printf 'idle' ;;
    preToolUse)
      case "${2:-}" in
        ask_user|AskUserQuestion|exit_plan_mode) printf 'awaiting' ;;
        *) printf 'working' ;;
      esac
      ;;
    userPromptSubmitted|permissionRequest|postToolUse|postToolUseFailure|subagentStart|subagentStop)
      printf 'working'
      ;;
    notification)
      case "${2:-}" in
        permission_prompt|elicitation_dialog) printf 'awaiting' ;;
        *) return 1 ;;
      esac
      ;;
    errorOccurred)
      if [ "${2:-false}" = true ]; then
        printf 'working'
      else
        printf 'idle'
      fi
      ;;
    abort) printf 'idle' ;;
    agentStop) printf 'idle' ;;
    sessionEnd) printf 'removed' ;;
    *) return 1 ;;
  esac
}

agent_clean_title() {
  local title=$1
  title=${title%%"$AGENT_RADAR_TITLE_SUFFIX"*}
  [ "$title" != "GitHub Copilot" ] || title=
  [ -n "$title" ] || title=-
  printf '%s' "$title"
}
