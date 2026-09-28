use crate::support::{parse_rows, write_executable, Scenario, StatusBar, NOW};
use std::fs;

#[test]
fn list_reports_only_live_copilot_panes_in_status_order() {
    let scenario = Scenario::new("cli-list")
        .session("alpha", 100)
        .session("beta", 200)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Awaiting Hook - GitHub Copilot")
        .copilot_pane("%2", "beta", 1, 2, 2000, "Working Hook - GitHub Copilot")
        .ordinary_pane("%3", "beta", 1, 3, 3000, "Regular shell")
        .build();
    scenario.write_state("%1", "awaiting");
    scenario.write_state("%2", "working");

    let rows = parse_rows(&scenario.run_text(&["--list"]));

    assert_eq!(rows.len(), 2, "rows: {rows:?}");
    assert_eq!(rows[0].pane, "%1");
    assert_eq!(rows[0].rank, 1);
    assert_eq!(rows[0].target, "alpha:1.1");
    assert_eq!(rows[0].title, "Awaiting Hook");
    assert_eq!(rows[1].pane, "%2");
    assert_eq!(rows[1].rank, 2);
}

#[test]
fn list_prunes_state_for_panes_that_no_longer_exist() {
    let scenario = Scenario::new("cli-prune")
        .session("alpha", 100)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Agent")
        .build();
    scenario.write_state("%1", "idle");
    scenario.write_state("%99", "working");

    scenario.run(&["--list"]);

    assert!(!scenario.state_path("%99").exists());
}

#[test]
fn status_commands_return_the_same_user_visible_rendering() {
    let scenario = Scenario::new("cli-status")
        .session("alpha", 100)
        .session("beta", 200)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Agent")
        .copilot_pane("%2", "beta", 1, 2, 2000, "Agent")
        .build();
    scenario.write_state("%1", "awaiting");
    scenario.write_state("%2", "working");

    let direct = scenario.run_text(&["--tmux-status", "alpha"]);
    scenario.run(&["--refresh"]);
    let cached = scenario.run_text(&["--tmux-status-cached", "alpha"]);

    assert_eq!(cached, direct);
    let bar = StatusBar::new(&cached);
    assert!(bar.has_icon_color("#f7768e"));
    assert!(bar.has_pane("1.1", "#f7768e", false));
    assert!(bar.has_current_session("1", "#f7768e"));
    assert!(bar.has_session_signal("2", "#e0af68"));
}

#[test]
fn preview_returns_terminal_content_without_interpreting_it() {
    let scenario = Scenario::new("cli-preview").build();
    scenario.set_capture("\u{1b}[31mred\u{1b}[0m\n");

    let output = scenario.run_text(&["preview", "%1"]);

    assert_eq!(output, "\u{1b}[31mred\u{1b}[0m");
    assert!(scenario
        .tmux_calls()
        .contains("capture-pane -p -e -t %1 -S -20"));
}

#[test]
fn invalid_command_returns_usage_error() {
    let scenario = Scenario::new("cli-invalid").build();

    let output = scenario
        .command()
        .arg("--not-a-command")
        .output()
        .expect("run invalid command");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("usage: agent-radar"));
}

#[test]
fn pinned_clock_does_not_create_the_shared_row_cache() {
    let scenario = Scenario::new("cli-pinned-cache")
        .session("alpha", 100)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Agent")
        .now(NOW)
        .build();
    scenario.write_state("%1", "working");

    scenario.run(&["--tmux-status", "alpha"]);

    assert!(!scenario.state_dir().join(".tmux-status.cache").exists());
}

#[test]
fn real_clock_populates_the_shared_row_cache() {
    let scenario = Scenario::new("cli-real-cache")
        .session("alpha", 100)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Agent")
        .build();
    scenario.write_state_value(
        "%1",
        serde_json::json!({
            "pane_id": "%1",
            "session_id": "test",
            "status": "working",
            "event": "test",
            "updated_at": "test",
            "updated_epoch": NOW
        }),
    );
    let mut command = scenario.command();
    command
        .env_remove("TMUX_AGENT_ENGINE_NOW")
        .env("TMUX_AGENT_ENGINE_CACHE_TTL", "3600")
        .args(["--tmux-status", "alpha"]);

    let output = command.output().expect("run status with real clock");

    assert!(output.status.success());
    assert!(scenario.state_dir().join(".tmux-status.cache").exists());
}

#[test]
fn popup_invokes_fzf_with_the_public_interaction_contract() {
    let scenario = Scenario::new("cli-popup")
        .session("alpha", 100)
        .copilot_pane("%1", "alpha", 1, 1, 1000, "Agent")
        .build();
    scenario.write_state("%1", "working");
    let fake_bin = scenario.root().join("bin");
    fs::create_dir_all(&fake_bin).expect("create fake bin");
    write_executable(
        &fake_bin.join("fzf"),
        r#"#!/usr/bin/env bash
printf '%s\n' "$@" >"$FZF_ARGS_FILE"
sed -n '1p'
"#,
    );
    let path = format!(
        "{}:{}",
        fake_bin.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let args_file = scenario.root().join("fzf-args");
    let mut command = scenario.command();
    command.env("PATH", path).env("FZF_ARGS_FILE", &args_file);

    let output = command.output().expect("open popup");

    assert!(output.status.success());
    let args = fs::read_to_string(args_file).expect("read fzf arguments");
    assert!(args.lines().any(|line| line == "--track"));
    assert!(args.lines().any(|line| line == "--with-nth=7"));
    assert!(args
        .lines()
        .any(|line| line.starts_with("--listen-unsafe=")));
    assert!(args
        .lines()
        .any(|line| line == "--preview-window=right,55%,border-left,follow"));
    assert!(!args
        .lines()
        .any(|line| line.starts_with("--bind=load:reload")));
}
