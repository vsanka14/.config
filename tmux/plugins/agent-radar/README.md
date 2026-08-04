# Agent Radar

Local tmux plugin for detecting Copilot CLI panes, showing their status in
tmux, and jumping to them from an fzf popup.

## Architecture

- `agent-radar.tmux` owns the popup binding and one `status-right` fragment.
- `bin/agent-radar` provides the popup, status renderer, refresh worker, and
  `--notify-lines` consumer API.
- `bin/agent-radar-hook` converts Copilot lifecycle events into privacy-safe
  per-pane state.
- `agents/copilot.sh` contains Copilot-specific process, title, and event rules.
- `lib/` contains shared configuration, detection, rendering, and notification
  logic.
- Runtime state defaults to
  `${XDG_STATE_HOME:-$HOME/.local/state}/agent-radar`.

The plugin never stores prompts or tool inputs.

## Tmux setup

Load the plugin after the rest of the status-bar configuration:

```tmux
set -g @agent-radar-on-change 'sketchybar --trigger agent_notify'
run-shell ~/.config/tmux/plugins/agent-radar/agent-radar.tmux
```

Supported options include:

```tmux
set -g @agent-radar-popup-key 'M-c'
set -g @agent-radar-status 'on'
set -g @agent-radar-done-ttl '3'
set -g @agent-radar-cache-ttl '2'
set -g @agent-radar-state-dir '/absolute/path/to/agent-radar'
```

Colors are configurable through the `@agent-radar-color-*` options defined in
`agent-radar.tmux`. A current session with no Copilot panes keeps a dim,
icon-only pill so the status affordance remains stable across session switches.
Re-run setup after changing `@agent-radar-state-dir` so the Copilot hook
descriptor uses the same directory.

## Copilot hook

Install or update the descriptor:

```bash
tmux/plugins/agent-radar/bin/agent-radar-setup install
tmux/plugins/agent-radar/bin/agent-radar-setup doctor
```

Setup generates the descriptor with the plugin's resolved absolute path,
migrates valid legacy pane state, and cleans only old Agent Radar state/cache
artifacts.

Copilot lifecycle events are the sole status source. Agent Radar uses public
tool and notification hooks for dialogs that need attention, completion hooks
to clear them, and session hooks to add or remove panes.

Copilot does not expose turn cancellation as a public hook. This setup
intentionally compensates with an untracked user extension at
`~/.copilot/extensions/agent-radar/extension.mjs`; it subscribes to the
Extension SDK's session `abort` event and forwards root-turn cancellation to
`agent-radar-hook abort`.

## Public commands

```bash
bin/agent-radar                         # interactive popup
bin/agent-radar --list
bin/agent-radar --tmux-status SESSION
bin/agent-radar --tmux-status-cached SESSION
bin/agent-radar --notify-lines
bin/agent-radar --refresh --notify
```

External consumers should use these modes rather than duplicating pane scans or
status precedence.

## Tests

```bash
bash -n agent-radar.tmux bin/* lib/*.sh agents/*.sh tests/*.sh
bash tests/engine-test.sh
bash tests/entrypoint-test.sh
bash tests/setup-test.sh
bash tests/boundary-test.sh
bash tests/popup-live-test.sh
```

The suite also guards the hot paths: cached status paints must not invoke tmux,
and full scans must not resolve tmux options at runtime.
