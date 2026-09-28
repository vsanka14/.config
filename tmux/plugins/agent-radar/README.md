# Agent Radar

Local tmux plugin for detecting Copilot CLI panes, showing their status in
tmux, and jumping to them from an fzf popup.

## Architecture

- `agent-radar.tmux` owns the popup binding and one `status-right` fragment.
- `bin/agent-radar` is the single installed runtime binary. Normal commands,
  Copilot hooks, and setup use its top-level, `hook`, and `setup` command modes.
- `src/model.rs` and `src/config.rs` define shared domain values and runtime
  configuration without performing I/O.
- `src/render.rs`, `src/scan.rs`, `src/status.rs`, and `src/notify.rs` own
  presentation, pane-state assembly, status access, and notification policy.
- `src/hooks.rs`, `src/refresh.rs`, and `src/setup.rs` coordinate the Copilot
  lifecycle, cached status publication, and installation workflows.
- `src/state.rs`, `src/tmux.rs`, and `src/popup.rs` isolate filesystem, tmux,
  process, and fzf integration. `src/lib.rs` is the small public facade.
- The previous shell implementation is preserved on the
  `vsankar/agent-radar-shell-legacy` branch.
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
set -g @agent-radar-done-ttl '3' # external notification duration
set -g @agent-radar-cache-ttl '2'
set -g @agent-radar-state-dir '/absolute/path/to/agent-radar'
```

Colors are configurable through the `@agent-radar-color-*` options defined in
`agent-radar.tmux`. A current session with no Copilot panes keeps a dim,
icon-only pill so the status affordance remains stable across session switches.
Completed panes remain `done` in the tmux status bar and popup until their next
lifecycle event or until the pane is visited. Pane/window/session selection and
pane focus acknowledge the completion automatically. `@agent-radar-done-ttl`
only controls how long external notification consumers such as SketchyBar
expose an unacknowledged completion.
Re-run setup after changing `@agent-radar-state-dir` so the Copilot hook
descriptor uses the same directory.

## Copilot hook

Install or update the descriptor:

```bash
tmux/plugins/agent-radar/bin/agent-radar setup install
tmux/plugins/agent-radar/bin/agent-radar setup doctor
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
`agent-radar hook abort`.

## Public commands

```bash
bin/agent-radar                         # interactive popup
bin/agent-radar --list
bin/agent-radar --tmux-status SESSION
bin/agent-radar --tmux-status-cached SESSION
bin/agent-radar --notify-lines
bin/agent-radar --ack-pane PANE
bin/agent-radar --refresh --notify
```

External consumers should use these modes rather than duplicating pane scans or
status precedence.

## Tests

Run the complete development validation workflow from the required tmux pane:

```bash
cd tmux/plugins/agent-radar
./scripts/dev-check
```

The workflow formats, tests, builds, and runs every acceptance test against the
newly built `target/release/agent-radar`. It does not change the live plugin.
After validation passes, install the candidate separately:

```bash
install -m 755 target/release/agent-radar bin/agent-radar
```

Behavior tests under `tests/integration/` launch the compiled CLI against
reusable fake tmux, process, session, and pane fixtures. They assert public
commands, hook input, generated descriptors, and session-scoped status output
rather than calling implementation modules. Shell tests under `tests/system/`
remain only for the actual tmux entrypoint, live fzf/tmux integration, and
plugin relocation boundaries.

The suite also guards the hot paths: cached status paints must not invoke tmux,
and full scans must not resolve tmux options at runtime. Normal status paints
read a session-scoped tmux option directly, so switching sessions does not
start a process or wait for an asynchronous `#()` result.
