use crate::support::{parse_rows, Scenario, NOW};

#[test]
fn completion_remains_visible_after_notification_ttl_until_acknowledged() {
    let scenario = Scenario::new("completion-ack")
        .session("work", 100)
        .copilot_pane("%8", "work", 1, 4, 8000, "Finished Task")
        .now(NOW + 100)
        .build();
    scenario.write_done("%8", NOW + 5);

    let before = parse_rows(&scenario.run_text(&["--list"]));
    assert_eq!(before[0].label, "✓ done");

    scenario.run(&["--ack-pane", "%8"]);

    let after = parse_rows(&scenario.run_text(&["--list"]));
    assert_eq!(after[0].label, "✓ idle");
}

#[test]
fn acknowledging_the_same_completion_twice_is_idempotent() {
    let scenario = Scenario::new("completion-idempotent")
        .session("work", 100)
        .copilot_pane("%8", "work", 1, 4, 8000, "Finished Task")
        .build();
    scenario.write_done("%8", NOW + 5);

    scenario.run(&["--ack-pane", "%8"]);
    let first = std::fs::read_to_string(scenario.state_dir().join(".ack/8"))
        .expect("first acknowledgement");
    scenario.run(&["--ack-pane", "%8"]);
    let second = std::fs::read_to_string(scenario.state_dir().join(".ack/8"))
        .expect("second acknowledgement");

    assert_eq!(second, first);
}

#[test]
fn a_new_non_completion_event_clears_the_previous_acknowledgement() {
    let scenario = Scenario::new("completion-clear")
        .session("work", 100)
        .copilot_pane("%8", "work", 1, 4, 8000, "Finished Task")
        .build();
    scenario.write_done("%8", NOW + 5);
    scenario.run(&["--ack-pane", "%8"]);
    assert!(scenario.state_dir().join(".ack/8").exists());

    scenario.hook(
        "%8",
        "userPromptSubmitted",
        serde_json::json!({"sessionId": "next-turn"}),
    );

    assert!(!scenario.state_dir().join(".ack/8").exists());
}
