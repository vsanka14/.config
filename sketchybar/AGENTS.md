# SketchyBar Agent Guide

## Scope

These instructions apply to everything under `sketchybar/`. Preserve the
Tokyo Night Moon styling and the separate laptop/external display profiles
unless a task explicitly requests a visual redesign.

## Configuration Map

- `sketchybarrc` creates all items, registers events, and assigns one script
  owner per event-driven feature.
- `plugins/aerospace.sh` renders workspace state and owns the workspace bounce.
- `../aerospace/aerospace.toml` emits `aerospace_workspace_change` with
  `FOCUSED_WORKSPACE`.
- `plugins/agent.sh` owns the `agent` item, surfacing Copilot agent status as an
  inline menu-bar label (see "Agent Notifications" below).
- Other files in `plugins/` update one independent item each.

## Agent Notifications

The `agent` item propagates Copilot agent status from tmux to the menu bar as an
inline label next to the agent icon (no popup). It is intentionally a thin
consumer:

- **Producer**: `../bin/tmux-agent-status` (a Copilot hook) fires
  `sketchybar --trigger agent_notify` on every real status transition, plus once
  more when a completion "done" flash expires. All SketchyBar calls there are
  guarded by `command -v sketchybar`, so machines without SketchyBar are
  unaffected.
- **Source of truth**: `plugins/agent.sh` re-derives the icon colour and the
  notable session list from `../bin/tmux-agent-picker --notify-lines` (which
  reuses the tmux pill/radar scan and priority folding). Do **not** reimplement
  the pane scan in the plugin — extend `--notify-lines` instead so the bar and
  tmux stay in lockstep.
- **Item contract**: `agent` is hidden (`drawing=off`) unless there is a
  **notable** agent (awaiting or done). Idle/working-only agents draw nothing, so
  the icon only appears when it needs attention. `plugins/agent.sh` is its single
  owner.
- **Transient vs blocking** is derived from state, not a trigger flag:
  - a completion ("done") shows a **transient** green label; it clears itself
    because the underlying `flash.kind=done` expires after `DONE_FLASH_TTL` in
    `../bin/tmux-agent-status`, which also re-fires `agent_notify` so the label
    drops promptly;
  - an awaiting-permission agent shows a **blocking** red label with a red-tinted
    item background, and it persists until the agent leaves the awaiting state.
- **Colours** mirror the tmux mapping: awaiting `#f7768e`, done `#3fb950`,
  other `#7dcfff`. Awaiting outranks done for the icon colour, label colour, and
  background tint. Idle/working-only agents are not notable, so the item is
  hidden for them.

If the `agent_notify` contract changes, update all three:
`../bin/tmux-agent-status`, `../bin/tmux-agent-picker`, and `plugins/agent.sh`.

## Event and Animation Architecture

Follow a **single observer, single render pass, single animation queue** model:

1. Add visible workspace items without subscribing each item to the shared
   workspace event.
2. Subscribe the hidden `workspace_observer` item once.
3. Let `plugins/aerospace.sh` calculate the complete state for every workspace.
4. Batch related `--set` operations into argument arrays and submit them in as
   few `sketchybar` calls as animation semantics allow.

This is a performance invariant, not just a style preference. Subscribing all
five workspace items and making each script update all five items creates 25
competing SketchyBar submissions per event. Each new animated write can cancel
the active queue for that property, producing visible restarts and choppiness.

The implementation intentionally uses two SketchyBar calls:

- One non-animated call switches workspace backgrounds immediately.
- One animated call updates all icon colors/offsets and appends every bounce
  keyframe to the same queue.

Do not split bounce keyframes across background processes, shell loops, sleeps,
or multiple event subscribers.

## Animation Timing

SketchyBar durations are 60 Hz-equivalent frame counts, not milliseconds. For
example, a duration of `6` is roughly 100 ms regardless of display refresh
rate.

`icon.y_offset` is integer-valued. Long durations over small distances repeat
the same integer position across several frames and can look like a pause.
Keep each keyframe duration roughly proportional to its travel distance:

- Rise: `0 -> BOUNCE_HEIGHT`
- Drop: `BOUNCE_HEIGHT -> BOUNCE_REBOUND`
- Settle: `BOUNCE_REBOUND -> BOUNCE_SETTLE`
- Finish: `BOUNCE_SETTLE -> 0`

The current `sin` curve eases into each target. When tuning the bounce:

- Change the constants at the top of `plugins/aerospace.sh`.
- Keep the total motion short enough to finish before normal rapid workspace
  switching queues another event.
- Prefer fewer meaningful frames over increasing duration for “smoothness.”
- Always finish at `icon.y_offset=0`.
- Ensure non-focused icons also target offset `0`, so interrupted animations
  cannot leave an icon displaced.

## Event Data and Startup

Use the `FOCUSED_WORKSPACE` value supplied by the custom event. Do not query
Aerospace again during a normal event. The fallback query in
`plugins/aerospace.sh` is required for `sketchybar --update`, startup, reload,
and direct script execution, where the event variable is absent.

If the event contract changes, update both:

- `../aerospace/aerospace.toml`
- `plugins/aerospace.sh`

## Extending Workspace Behavior

When adding a workspace:

1. Add its icon to `SPACE_ICONS` in `sketchybarrc`.
2. Add its color to `WORKSPACE_COLORS` in `plugins/aerospace.sh`.
3. Update both workspace loops to include the new ID.
4. Keep `workspace_observer` as the only workspace-event subscriber.
5. Confirm focused and non-focused state are both included in the batched
   update.

For a new animated workspace property, add every keyframe to `animation_args`
in one invocation. For an immediate property, add it to `background_args` or a
renamed immediate-state array. Never have multiple scripts write the same
animated property for the same event.

## Shell Compatibility

Scripts use `#!/bin/bash`, which is Bash 3.2 on macOS. Use indexed arrays with
explicit numeric indices; do not use Bash 4 associative arrays (`declare -A`),
`mapfile`, or other newer Bash features. Quote expanded item names and values.

## Validation

After editing:

```bash
bash -n sketchybar/sketchybarrc sketchybar/plugins/*.sh
shellcheck sketchybar/sketchybarrc sketchybar/plugins/*.sh  # when installed
sketchybar --reload
focused="$(aerospace list-workspaces --focused)"
sketchybar --trigger aerospace_workspace_change \
  "FOCUSED_WORKSPACE=$focused"
sketchybar --query workspace_observer
sketchybar --query "space.$focused"
```

The observer should be subscribed with `drawing=off`, the focused background
should be on, and the focused icon should settle at `y_offset=0`.

For the agent notification feature:

```bash
bash -n bin/tmux-agent-status bin/tmux-agent-picker sketchybar/plugins/agent.sh
bash tests/tmux-agent-picker-test.sh          # covers --notify-lines
bin/tmux-agent-picker --notify-lines          # COLOR + LINE rows, or empty
sketchybar --reload
sketchybar --trigger agent_notify
sketchybar --query agent                      # drawing reflects tracked agents
```
