use crate::support::Scenario;
use std::fs;

#[test]
fn contended_refresh_leaves_work_for_the_next_lock_owner() {
    let scenario = Scenario::new("concurrency-pending")
        .session("work", 100)
        .copilot_pane("%1", "work", 1, 1, 1000, "Agent")
        .env("TMUX_AGENT_ENGINE_STATUS_LOCK_STALE", "999999999")
        .build();
    scenario.write_state("%1", "working");
    let status_dir = scenario.state_dir().join(".status");
    fs::create_dir_all(status_dir.join(".refresh.lock")).expect("create held lock");

    scenario.run(&["--refresh"]);

    assert!(status_dir.join(".pending").exists());

    fs::remove_dir(status_dir.join(".refresh.lock")).expect("release lock");
    scenario.run(&["--refresh"]);

    assert!(!status_dir.join(".pending").exists());
    assert!(!scenario.session_option("work").is_empty());
}

#[test]
fn cached_status_reads_the_published_value_without_calling_tmux() {
    let scenario = Scenario::new("concurrency-cached-status")
        .session("work", 100)
        .copilot_pane("%1", "work", 1, 1, 1000, "Agent")
        .build();
    scenario.write_state("%1", "working");
    scenario.run(&["--refresh"]);
    let expected = scenario.session_option("work");
    fs::write(scenario.root().join("tmux-calls"), "").expect("clear tmux calls");

    let cached = scenario.run_text(&["--tmux-status-cached", "work"]);

    assert_eq!(cached, expected);
    assert_eq!(scenario.tmux_calls(), "");
}

#[test]
fn multiple_refresh_requests_publish_the_latest_state() {
    let scenario = Scenario::new("concurrency-latest")
        .session("work", 100)
        .copilot_pane("%1", "work", 1, 1, 1000, "Agent")
        .build();
    scenario.write_state("%1", "working");
    scenario.run(&["--refresh"]);

    scenario.write_state("%1", "awaiting");
    scenario.run(&["--refresh"]);

    let status = scenario.session_option("work");
    assert!(status.contains("#[fg=#f7768e,bold]1.1 "), "{status}");
}
