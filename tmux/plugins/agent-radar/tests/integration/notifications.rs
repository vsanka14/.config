use crate::support::{Scenario, NOW};
use std::thread;
use std::time::Duration;

#[test]
fn notification_output_prioritizes_awaiting_and_reports_done_sessions() {
    let scenario = Scenario::new("notifications-output")
        .session("solo", 100)
        .session("duo", 200)
        .copilot_pane("%1", "solo", 1, 1, 1000, "Solo")
        .copilot_pane("%2", "duo", 1, 1, 2000, "Duo")
        .build();
    scenario.write_state("%1", "awaiting");
    scenario.write_done("%2", NOW + 5);

    let output = scenario.run_text(&["--notify-lines"]);

    assert_eq!(
        output,
        "COLOR\t#f7768e\nLINE\tsolo\tawaiting\nLINE\tduo\tdone"
    );
}

#[test]
fn expired_completion_is_hidden_from_external_notifications() {
    let scenario = Scenario::new("notifications-expired")
        .session("work", 100)
        .copilot_pane("%1", "work", 1, 1, 1000, "Agent")
        .now(NOW + 100)
        .build();
    scenario.write_done("%1", NOW + 5);

    let output = scenario.run_text(&["--notify-lines"]);

    assert_eq!(output, "COLOR\t#7dcfff");
}

#[test]
fn no_agents_produces_no_external_notification_output() {
    let scenario = Scenario::new("notifications-empty")
        .session("work", 100)
        .ordinary_pane("%1", "work", 1, 1, 1000, "Shell")
        .build();

    assert_eq!(scenario.run_text(&["--notify-lines"]), "");
}

#[test]
fn change_callback_runs_after_a_notifying_hook_refresh() {
    let scenario = Scenario::new("notifications-callback")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 7000, "Agent")
        .build();
    let marker = scenario.root().join("notified");
    let callback = format!("printf changed > '{}'", marker.display());

    scenario.run_with_stdin(
        &["hook", "preToolUse"],
        r#"{"sessionId":"test","toolName":"bash"}"#,
        &[
            ("TMUX_PANE", "%7"),
            ("AGENT_RADAR_ON_CHANGE", callback.as_str()),
        ],
    );

    for _ in 0..40 {
        if marker.exists() {
            break;
        }
        thread::sleep(Duration::from_millis(25));
    }
    assert_eq!(
        std::fs::read_to_string(marker).expect("notification marker"),
        "changed"
    );
}
