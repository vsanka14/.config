use agent_radar::boundary::{self, Config, Tmux};
use std::env;
use std::fs;
use std::io;
use std::path::PathBuf;
use std::process::{Command as ProcessCommand, ExitCode, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Debug, Eq, PartialEq)]
enum Command {
    Popup,
    Preview(String),
    List,
    TmuxStatus(String),
    TmuxStatusCached(String),
    NotifyLines,
    AcknowledgePane(String),
    Refresh { notify: bool },
    Hook(Option<String>),
    SetupInstall,
    SetupDoctor,
}

fn parse_command(args: &[String]) -> Result<Command, String> {
    match args {
        [] => Ok(Command::Popup),
        [command, pane] if command == "preview" => Ok(Command::Preview(pane.clone())),
        [command] if command == "--list" => Ok(Command::List),
        [command, session] if command == "--tmux-status" => Ok(Command::TmuxStatus(session.clone())),
        [command, session] if command == "--tmux-status-cached" => Ok(Command::TmuxStatusCached(session.clone())),
        [command] if command == "--notify-lines" => Ok(Command::NotifyLines),
        [command, pane] if command == "--ack-pane" => Ok(Command::AcknowledgePane(pane.clone())),
        [command] if command == "--refresh" => Ok(Command::Refresh { notify: false }),
        [command, notify] if command == "--refresh" && notify == "--notify" => Ok(Command::Refresh { notify: true }),
        [command] if command == "hook" => Ok(Command::Hook(None)),
        [command, event] if command == "hook" => Ok(Command::Hook(Some(event.clone()))),
        [command, action] if command == "setup" && action == "install" => Ok(Command::SetupInstall),
        [command, action] if command == "setup" && action == "doctor" => Ok(Command::SetupDoctor),
        _ => Err("usage: agent-radar [preview PANE_ID|--list|--tmux-status SESSION|--tmux-status-cached SESSION|--notify-lines|--ack-pane PANE_ID|--refresh [--notify]|hook EVENT|setup <install|doctor>]".into()),
    }
}

fn print(value: io::Result<String>) -> Result<(), String> {
    let value = value.map_err(|error| error.to_string())?;
    if !value.is_empty() {
        print!("{value}");
    }
    Ok(())
}

fn popup(config: &Config) -> Result<(), String> {
    let tmux = Tmux::new(config.tmux.clone());
    fs::create_dir_all(&config.state_dir).map_err(|error| error.to_string())?;
    let popup_name = format!(
        ".agent-radar.{}.{:x}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let popup_base = env::var_os("TMPDIR")
        .map(PathBuf::from)
        .filter(|base| base.join(&popup_name).join("fzf.sock").as_os_str().len() < 100)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let popup_dir = popup_base.join(popup_name);
    fs::create_dir(&popup_dir).map_err(|error| error.to_string())?;
    let socket = popup_dir.join("fzf.sock");
    let rows = boundary::rows_text(
        config,
        "full",
        env::var("NO_COLOR").ok().as_deref() != Some("1"),
    )
    .map_err(|error| error.to_string())?;
    let self_path = env::current_exe().map_err(|error| error.to_string())?;
    let child = ProcessCommand::new("fzf")
        .args(["--ansi", "--track", "--reverse", "--border=rounded", "--delimiter=\t", "--with-nth=7",
            "--border-label=  Agents ", "--border-label-pos=3", "--prompt=  ", "--pointer=▶", "--padding=1",
            "--color=bg:-1,fg+:#c0caf5,bg+:#292e42,hl:#7aa2f7,hl+:#7dcfff,gutter:#3b4261,border:#27a1b9,label:#7dcfff,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,header:#565f89,info:#565f89,spinner:#7dcfff",
            "--header=STATUS      TARGET                      TITLE", "--preview-window=right,55%,border-left,follow"])
        .arg(format!("--listen-unsafe={}", socket.display()))
        .arg(format!("--preview={} preview {{2}}", shell_quote(&self_path.to_string_lossy())))
        .stdin(Stdio::piped()).stdout(Stdio::piped()).spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(error) => {
            let _ = fs::remove_file(&socket);
            let _ = fs::remove_dir(&popup_dir);
            return Err(format!("fzf is required: {error}"));
        }
    };
    for _ in 0..40 {
        if socket.exists() {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    let registration = socket
        .exists()
        .then(|| boundary::register_popup(config, &socket))
        .transpose()
        .ok()
        .flatten();
    use std::io::Write;
    let selection = (|| -> io::Result<String> {
        child
            .stdin
            .take()
            .ok_or_else(|| io::Error::new(io::ErrorKind::BrokenPipe, "fzf stdin unavailable"))?
            .write_all(rows.as_bytes())?;
        let output = child.wait_with_output()?;
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
    })();
    if let Some(registration) = registration {
        let _ = fs::remove_file(registration);
    }
    let _ = fs::remove_file(&socket);
    let _ = fs::remove_dir(&popup_dir);
    let selection = selection.map_err(|error| error.to_string())?;
    if let Some((pane, session)) = selection
        .split('\t')
        .nth(1)
        .zip(selection.split('\t').nth(2))
    {
        tmux.run(&["switch-client", "-t", session])
            .map_err(|error| error.to_string())?;
        tmux.run(&["select-pane", "-t", pane])
            .map_err(|error| error.to_string())?;
        let _ = tmux.run(&["refresh-client", "-S"]);
    }
    Ok(())
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
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
fn hook_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("AGENT_RADAR_HOOK_BIN") {
        return Ok(PathBuf::from(path));
    }
    let binary = env::current_exe().map_err(|error| error.to_string())?;
    let directory = binary
        .parent()
        .ok_or_else(|| "agent-radar executable has no parent directory".to_owned())?;
    Ok(directory.join("agent-radar-hook"))
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
        let value = value.trim();
        if !value.is_empty() {
            configured.state_dir = PathBuf::from(value);
        }
    }
    configured
}
fn dispatch(command: Command, config: &Config) -> Result<(), String> {
    match command {
        Command::Popup => popup(config),
        Command::Preview(pane) => {
            let output = ProcessCommand::new(&config.tmux)
                .args(["capture-pane", "-p", "-e", "-t", &pane, "-S", "-20"])
                .output()
                .map_err(|e| e.to_string())?;
            if !output.status.success() {
                return Err(String::from_utf8_lossy(&output.stderr).into());
            }
            print!("{}", String::from_utf8_lossy(&output.stdout));
            Ok(())
        }
        Command::List => {
            let rows = boundary::rows_text(
                config,
                "full",
                env::var("NO_COLOR").ok().as_deref() != Some("1"),
            )
            .map_err(|e| e.to_string())?;
            if !rows.is_empty() {
                println!("{rows}");
            }
            Ok(())
        }
        Command::TmuxStatus(session) => print(boundary::status(config, &session)),
        Command::TmuxStatusCached(session) => print(boundary::cached_status(config, &session)),
        Command::NotifyLines => {
            let records = boundary::notification_text(config).map_err(|e| e.to_string())?;
            if !records.is_empty() {
                println!("{records}");
            }
            Ok(())
        }
        Command::AcknowledgePane(pane) => {
            boundary::acknowledge(config, &pane).map_err(|e| e.to_string())?;
            boundary::refresh(config, true).map_err(|e| e.to_string())
        }
        Command::Refresh { notify } => boundary::refresh(config, notify).map_err(|e| e.to_string()),
        // Copilot hooks intentionally remain best effort: user interaction must
        // never fail just because status telemetry cannot be updated.
        Command::Hook(event) => match boundary::hook(config, event.as_deref(), &mut io::stdin()) {
            Ok(()) => Ok(()),
            Err(error) if env::var_os("AGENT_RADAR_HOOK_DEBUG").is_some() => Err(error.to_string()),
            Err(_) => Ok(()),
        },
        Command::SetupInstall => {
            let legacy = env::var_os("AGENT_RADAR_LEGACY_STATE_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|| copilot_root().join("agent-status"));
            let setup_config = configured_setup_config(config);
            let hook = hook_path()?;
            boundary::install(&setup_config, &descriptor_path(), &hook, &legacy)
                .map_err(|e| e.to_string())?;
            println!("installed {}", descriptor_path().display());
            Ok(())
        }

        Command::SetupDoctor => {
            let setup_config = configured_setup_config(config);
            let hook = hook_path()?;
            let (output, ok) = boundary::doctor(&setup_config, &descriptor_path(), &hook);
            println!("{output}");
            if ok {
                Ok(())
            } else {
                Err("doctor found problems".into())
            }
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match parse_command(&args).and_then(|command| dispatch(command, &Config::from_env())) {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("agent-radar: {message}");
            ExitCode::from(1)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn accepts_the_complete_contract_command_shape() {
        assert_eq!(parse_command(&[]), Ok(Command::Popup));
        assert_eq!(
            parse_command(&["--refresh".into(), "--notify".into()]),
            Ok(Command::Refresh { notify: true })
        );
        assert_eq!(parse_command(&["hook".into()]), Ok(Command::Hook(None)));
        assert_eq!(
            parse_command(&["hook".into(), "agentStop".into()]),
            Ok(Command::Hook(Some("agentStop".into())))
        );
        assert_eq!(
            parse_command(&["setup".into(), "doctor".into()]),
            Ok(Command::SetupDoctor)
        );
    }
}
