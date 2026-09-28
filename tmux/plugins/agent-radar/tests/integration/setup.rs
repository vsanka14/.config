use crate::support::{binary, write_executable, TempDir};
use serde_json::Value;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

#[test]
fn install_generates_the_public_hook_descriptor() {
    let temp = TempDir::new("setup-descriptor");
    let state = temp.path().join("state");
    let copilot = temp.path().join("copilot");

    let output = setup_command(&temp, &state, &copilot)
        .args(["setup", "install"])
        .output()
        .expect("install descriptor");
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let descriptor: Value = serde_json::from_slice(
        &fs::read(copilot.join("hooks/tmux-agent-status.json")).expect("read descriptor"),
    )
    .expect("parse descriptor");
    let hooks = descriptor["hooks"].as_object().expect("hooks object");
    assert_eq!(descriptor["version"], 1);
    assert_eq!(hooks.len(), 12);
    assert_eq!(
        hooks["notification"][0]["matcher"],
        "permission_prompt|elicitation_dialog"
    );
    for commands in hooks.values() {
        for command in commands.as_array().expect("hook command list") {
            assert!(command["command"]
                .as_str()
                .expect("hook command")
                .contains(&format!("{} hook ", binary())));
        }
    }
}

#[test]
fn install_migrates_only_valid_newer_legacy_state() {
    let temp = TempDir::new("setup-migration");
    let state = temp.path().join("state");
    let copilot = temp.path().join("copilot");
    let legacy = copilot.join("agent-status");
    fs::create_dir_all(&legacy).expect("create legacy state");
    fs::create_dir_all(&state).expect("create current state");
    fs::write(
        legacy.join("7.json"),
        r#"{"pane_id":"%7","status":"working","updated_epoch":300}"#,
    )
    .expect("write valid legacy state");
    fs::write(legacy.join("8.json"), r#"{"prompt":"must not migrate"}"#)
        .expect("write invalid legacy state");
    fs::write(
        legacy.join("9.json"),
        r#"{"pane_id":"%9","status":"idle","updated_epoch":100}"#,
    )
    .expect("write old legacy state");
    fs::write(
        state.join("9.json"),
        r#"{"pane_id":"%9","status":"working","updated_epoch":200}"#,
    )
    .expect("write newer current state");

    let output = setup_command(&temp, &state, &copilot)
        .args(["setup", "install"])
        .output()
        .expect("install with migration");
    assert!(output.status.success());

    assert!(state.join("7.json").exists());
    assert!(!state.join("8.json").exists());
    let pane_nine: Value =
        serde_json::from_slice(&fs::read(state.join("9.json")).expect("read pane nine"))
            .expect("parse pane nine");
    assert_eq!(pane_nine["status"], "working");
    assert!(!legacy.join("7.json").exists());
}

#[test]
fn install_rejects_a_symlinked_state_directory() {
    let temp = TempDir::new("setup-symlink");
    let target = temp.path().join("target");
    let state = temp.path().join("state-link");
    let copilot = temp.path().join("copilot");
    fs::create_dir_all(&target).expect("create symlink target");
    std::os::unix::fs::symlink(&target, &state).expect("create state symlink");

    let output = setup_command(&temp, &state, &copilot)
        .args(["setup", "install"])
        .output()
        .expect("install with symlink");

    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("symlinked state directory"));
}

#[test]
fn doctor_accepts_an_installed_descriptor_and_secure_state_directory() {
    let temp = TempDir::new("setup-doctor");
    let state = temp.path().join("state");
    let copilot = temp.path().join("copilot");
    let fake_bin = temp.path().join("bin");
    fs::create_dir_all(&fake_bin).expect("create fake bin");
    write_executable(&fake_bin.join("tmux"), "#!/bin/sh\nexit 0\n");
    write_executable(&fake_bin.join("fzf"), "#!/bin/sh\nexit 0\n");

    let mut install = setup_command(&temp, &state, &copilot);
    install.env("PATH", &fake_bin).args(["setup", "install"]);
    assert!(install.output().expect("install").status.success());

    let mut doctor = setup_command(&temp, &state, &copilot);
    doctor.env("PATH", &fake_bin).args(["setup", "doctor"]);
    let output = doctor.output().expect("run doctor");

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(String::from_utf8_lossy(&output.stdout).contains("ok - Copilot hook descriptor"));
    assert_eq!(
        fs::metadata(&state)
            .expect("state metadata")
            .permissions()
            .mode()
            & 0o777,
        0o700
    );
}

#[test]
fn install_uses_the_state_directory_configured_in_tmux() {
    let temp = TempDir::new("setup-tmux-state");
    let configured_state = temp.path().join("configured-state");
    let copilot = temp.path().join("copilot");
    let fake_bin = temp.path().join("bin");
    fs::create_dir_all(&fake_bin).expect("create fake bin");
    write_executable(
        &fake_bin.join("tmux"),
        "#!/bin/sh\nprintf '%s\\n' \"$SETUP_STATE_OPTION\"\n",
    );
    let mut command = Command::new(binary());
    command
        .env("HOME", temp.path().join("home"))
        .env("COPILOT_HOME", &copilot)
        .env("AGENT_RADAR_BIN", binary())
        .env("SETUP_STATE_OPTION", &configured_state)
        .env("PATH", &fake_bin)
        .args(["setup", "install"]);

    let output = command.output().expect("install with tmux state option");

    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let descriptor: Value = serde_json::from_slice(
        &fs::read(copilot.join("hooks/tmux-agent-status.json")).expect("read descriptor"),
    )
    .expect("parse descriptor");
    for commands in descriptor["hooks"].as_object().expect("hooks").values() {
        for command in commands.as_array().expect("hook list") {
            assert!(command["command"]
                .as_str()
                .expect("hook command")
                .starts_with(&format!(
                    "env AGENT_RADAR_STATE_DIR={} ",
                    configured_state.display()
                )));
        }
    }
}

fn setup_command(temp: &TempDir, state: &Path, copilot: &Path) -> Command {
    let mut command = Command::new(binary());
    command
        .env("HOME", temp.path().join("home"))
        .env("COPILOT_HOME", copilot)
        .env("AGENT_RADAR_STATE_DIR", state)
        .env("AGENT_RADAR_BIN", binary());
    command
}
