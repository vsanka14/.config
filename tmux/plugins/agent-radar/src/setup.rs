use crate::state;
use crate::{Config, Tmux};
use serde_json::{json, Value};
use std::env;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

pub fn descriptor(config: &Config, executable: &Path) -> Value {
    let command = format!(
        "env AGENT_RADAR_STATE_DIR={} {} hook",
        shell_quote(&config.state_dir.to_string_lossy()),
        shell_quote(&executable.to_string_lossy())
    );
    let events = [
        "sessionStart",
        "userPromptSubmitted",
        "permissionRequest",
        "notification",
        "preToolUse",
        "postToolUse",
        "postToolUseFailure",
        "errorOccurred",
        "agentStop",
        "sessionEnd",
        "subagentStart",
        "subagentStop",
    ];
    let mut hooks = serde_json::Map::new();
    for event in events {
        let mut item =
            json!({"type":"command","command":format!("{command} {event}"),"timeoutSec":5});
        if event == "notification" {
            item["matcher"] = json!("permission_prompt|elicitation_dialog");
        }
        hooks.insert(event.into(), Value::Array(vec![item]));
    }
    json!({"version":1,"disableAllHooks":false,"hooks":hooks})
}

fn shell_quote(value: &str) -> String {
    if !value.is_empty()
        && value.bytes().all(|byte| {
            byte.is_ascii_alphanumeric() || matches!(byte, b'/' | b'.' | b'_' | b'-' | b':' | b'=')
        })
    {
        value.into()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

pub fn install(
    config: &Config,
    descriptor_path: &Path,
    executable: &Path,
    legacy: &Path,
) -> io::Result<()> {
    state::secure_dir(&config.state_dir)?;
    state::migrate(config, legacy)?;
    let parent = descriptor_path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "descriptor has no parent"))?;
    state::secure_dir(parent)?;
    state::atomic_write(
        descriptor_path,
        &serde_json::to_vec_pretty(&descriptor(config, executable))
            .expect("descriptor serialization"),
    )?;
    state::clean_legacy(legacy, &config.state_dir)
}

pub fn doctor(config: &Config, descriptor_path: &Path, executable: &Path) -> (String, bool) {
    let mut lines = Vec::new();
    let mut ok = true;
    for (name, executable) in [("tmux", config.tmux.as_str()), ("fzf", "fzf")] {
        let present = executable_in_path(executable);
        lines.push(format!(
            "{} - {}{}",
            if present { "ok" } else { "not ok" },
            if present { "" } else { "missing " },
            name
        ));
        ok &= present;
    }
    let valid_descriptor = fs::read(descriptor_path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .is_some_and(|value| value == descriptor(config, executable));
    lines.push(format!(
        "{} - Copilot hook descriptor",
        if valid_descriptor { "ok" } else { "not ok" }
    ));
    ok &= valid_descriptor;
    let mode_ok = state::permissions_are_secure(&config.state_dir);
    lines.push(format!(
        "{} - state directory permissions",
        if mode_ok { "ok" } else { "not ok" }
    ));
    (lines.join("\n"), ok && mode_ok)
}

fn executable_in_path(command: &str) -> bool {
    let path = Path::new(command);
    if path.components().count() > 1 {
        return fs::metadata(path).is_ok_and(|metadata| {
            metadata.is_file() && metadata.permissions().mode() & 0o111 != 0
        });
    }
    env::var_os("PATH").is_some_and(|paths| {
        env::split_paths(&paths).any(|directory| {
            fs::metadata(directory.join(command)).is_ok_and(|metadata| {
                metadata.is_file() && metadata.permissions().mode() & 0o111 != 0
            })
        })
    })
}

pub fn install_default(config: &Config) -> Result<PathBuf, String> {
    let descriptor = descriptor_path();
    install(
        &configured_setup_config(config),
        &descriptor,
        &executable_path()?,
        &legacy_state_dir(),
    )
    .map_err(|error| error.to_string())?;
    Ok(descriptor)
}

pub fn doctor_default(config: &Config) -> Result<(String, bool), String> {
    Ok(doctor(
        &configured_setup_config(config),
        &descriptor_path(),
        &executable_path()?,
    ))
}

fn copilot_root() -> PathBuf {
    env::var_os("COPILOT_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env::var("HOME").unwrap_or_default()).join(".copilot"))
}

fn descriptor_path() -> PathBuf {
    env::var_os("AGENT_RADAR_COPILOT_DESCRIPTOR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            env::var_os("AGENT_RADAR_COPILOT_HOOK_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| copilot_root().join("hooks"))
                .join("tmux-agent-status.json")
        })
}

fn executable_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("AGENT_RADAR_BIN") {
        return Ok(path.into());
    }
    env::current_exe().map_err(|error| error.to_string())
}

fn legacy_state_dir() -> PathBuf {
    env::var_os("AGENT_RADAR_LEGACY_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| copilot_root().join("agent-status"))
}

fn configured_setup_config(config: &Config) -> Config {
    if env::var_os("AGENT_RADAR_STATE_DIR").is_some()
        || env::var_os("TMUX_AGENT_ENGINE_STATE_DIR").is_some()
    {
        return config.clone();
    }
    let mut configured = config.clone();
    if let Ok(value) =
        Tmux::new(config.tmux.clone()).output(&["show-option", "-gqv", "@agent-radar-state-dir"])
    {
        if !value.trim().is_empty() {
            configured.state_dir = value.trim().into();
        }
    }
    configured
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn makes_descriptor_with_exact_events() {
        let config = Config::from_env();
        let descriptor = descriptor(&config, Path::new("/agent-radar"));
        assert_eq!(descriptor["hooks"].as_object().expect("hooks").len(), 12);
        assert_eq!(
            descriptor["hooks"]["preToolUse"][0]["command"],
            format!(
                "env AGENT_RADAR_STATE_DIR={} /agent-radar hook preToolUse",
                config.state_dir.display()
            )
        );
        assert_eq!(
            descriptor["hooks"]["notification"][0]["matcher"],
            "permission_prompt|elicitation_dialog"
        );
    }
}
