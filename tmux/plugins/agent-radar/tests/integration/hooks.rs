use crate::support::Scenario;
use serde_json::json;
use std::io::Write;
use std::process::Stdio;

#[test]
fn prompt_and_tool_events_drive_the_visible_lifecycle() {
    let scenario = Scenario::new("hooks-lifecycle")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();

    scenario.hook("%7", "sessionStart", json!({"sessionId": "session-1"}));
    assert_eq!(scenario.read_state("%7")["status"], "idle");

    scenario.hook(
        "%7",
        "userPromptSubmitted",
        json!({"sessionId": "session-1", "prompt": "must not persist"}),
    );
    assert_eq!(scenario.read_state("%7")["status"], "working");

    scenario.hook(
        "%7",
        "preToolUse",
        json!({
            "sessionId": "session-1",
            "toolName": "ask_user",
            "toolInput": {"secret": "must not persist"}
        }),
    );
    let awaiting = scenario.read_state("%7");
    assert_eq!(awaiting["status"], "awaiting");
    assert_eq!(awaiting["tool_name"], "ask_user");

    scenario.hook(
        "%7",
        "postToolUse",
        json!({"sessionId": "session-1", "toolName": "ask_user"}),
    );
    assert_eq!(scenario.read_state("%7")["status"], "working");

    scenario.hook("%7", "agentStop", json!({"sessionId": "session-1"}));
    let completed = scenario.read_state("%7");
    assert_eq!(completed["status"], "idle");
    assert_eq!(completed["flash"]["kind"], "done");
}

#[test]
fn batched_ask_user_is_detected_without_persisting_payloads() {
    let scenario = Scenario::new("hooks-batched")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();

    scenario.hook(
        "%7",
        "preToolUse",
        json!({
            "sessionId": "session-1",
            "toolCalls": [
                {"name": "bash", "args": "{\"secret\":\"must not persist\"}"},
                {"name": "ask_user", "args": "{\"question\":\"must not persist\"}"}
            ]
        }),
    );

    let state = scenario.read_state("%7");
    assert_eq!(state["status"], "awaiting");
    assert_eq!(state["tool_name"], "ask_user");
    let persisted = std::fs::read_to_string(scenario.state_path("%7")).expect("read state");
    assert!(!persisted.contains("must not persist"));
    assert!(!persisted.contains("toolCalls"));
}

#[test]
fn recoverable_and_terminal_errors_have_different_visible_states() {
    let scenario = Scenario::new("hooks-errors")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();

    scenario.hook(
        "%7",
        "errorOccurred",
        json!({"sessionId": "session-1", "recoverable": true}),
    );
    assert_eq!(scenario.read_state("%7")["status"], "working");

    scenario.hook(
        "%7",
        "errorOccurred",
        json!({"sessionId": "session-1", "recoverable": false}),
    );
    let state = scenario.read_state("%7");
    assert_eq!(state["status"], "idle");
    assert!(state["flash"].is_null());
}

#[test]
fn abort_settles_the_agent_without_successful_completion() {
    let scenario = Scenario::new("hooks-abort")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();
    scenario.hook(
        "%7",
        "userPromptSubmitted",
        json!({"sessionId": "session-1"}),
    );

    scenario.hook("%7", "abort", json!({"sessionId": "session-1"}));

    let state = scenario.read_state("%7");
    assert_eq!(state["status"], "idle");
    assert!(state["flash"].is_null());
}

#[test]
fn session_end_removes_the_agent_from_public_output() {
    let scenario = Scenario::new("hooks-session-end")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();
    scenario.hook("%7", "sessionStart", json!({"sessionId": "session-1"}));

    scenario.run_with_stdin(
        &["hook", "sessionEnd"],
        r#"{"sessionId":"session-1"}"#,
        &[("TMUX_PANE", "%7")],
    );

    assert!(!scenario.state_path("%7").exists());
    assert!(!scenario.session_option("work").contains("1.1 "));
}

#[test]
fn hook_resolves_the_tmux_pane_from_process_ancestry() {
    let scenario = Scenario::new("hooks-ancestry")
        .session("work", 100)
        .copilot_pane("%8", "work", 1, 1, 700, "Agent")
        .process(900, 701, "bash")
        .build();
    let mut command = scenario.command();
    command
        .args(["hook", "sessionStart"])
        .env_remove("TMUX_PANE")
        .env("TMUX_AGENT_STATUS_PROCESS_PID", "900")
        .env("TMUX_AGENT_STATUS_REFRESH", "0")
        .stdin(Stdio::piped());
    let mut child = command.spawn().expect("spawn ancestry hook");
    child
        .stdin
        .take()
        .expect("hook stdin")
        .write_all(br#"{"sessionId":"resolved-session"}"#)
        .expect("write hook payload");

    let output = child.wait_with_output().expect("wait for hook");

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(scenario.read_state("%8")["session_id"], "resolved-session");
}

#[test]
fn late_session_start_does_not_overwrite_active_work() {
    let scenario = Scenario::new("hooks-late-start")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();
    scenario.hook(
        "%7",
        "userPromptSubmitted",
        json!({"sessionId": "session-1"}),
    );

    scenario.hook("%7", "sessionStart", json!({"sessionId": "session-1"}));

    assert_eq!(scenario.read_state("%7")["status"], "working");
}

#[test]
fn pane_state_permissions_are_private() {
    use std::os::unix::fs::PermissionsExt;

    let scenario = Scenario::new("hooks-permissions")
        .session("work", 100)
        .copilot_pane("%7", "work", 1, 1, 700, "Agent")
        .build();

    scenario.hook("%7", "sessionStart", json!({"sessionId": "session-1"}));

    assert_eq!(
        std::fs::metadata(scenario.state_dir())
            .expect("state directory metadata")
            .permissions()
            .mode()
            & 0o777,
        0o700
    );
    assert_eq!(
        std::fs::metadata(scenario.state_path("%7"))
            .expect("state file metadata")
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
}
