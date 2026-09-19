use crate::state::{atomic_write, is_symlink, secure_dir};
use crate::{rows_text, Config, RowMode};
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub fn open(config: &Config) -> Result<(), String> {
    secure_dir(&config.state_dir).map_err(|error| error.to_string())?;
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
    fs::create_dir_all(&popup_base).map_err(|error| error.to_string())?;
    let popup_dir = popup_base.join(popup_name);
    fs::create_dir(&popup_dir).map_err(|error| error.to_string())?;
    let socket = popup_dir.join("fzf.sock");
    let rows = rows_text(
        config,
        RowMode::Full,
        env::var("NO_COLOR").ok().as_deref() != Some("1"),
    )
    .map_err(|error| error.to_string())?;
    let self_path = env::current_exe().map_err(|error| error.to_string())?;
    let child = Command::new("fzf")
        .args([
            "--ansi",
            "--track",
            "--reverse",
            "--border=rounded",
            "--delimiter=\t",
            "--with-nth=7",
            "--border-label=  Agents ",
            "--border-label-pos=3",
            "--prompt=  ",
            "--pointer=▶",
            "--padding=1",
            "--color=bg:-1,fg+:#c0caf5,bg+:#292e42,hl:#7aa2f7,hl+:#7dcfff,gutter:#3b4261,border:#27a1b9,label:#7dcfff,prompt:#7dcfff,pointer:#bb9af7,marker:#9ece6a,header:#565f89,info:#565f89,spinner:#7dcfff",
            "--header=STATUS      TARGET                      TITLE",
            "--preview-window=right,55%,border-left,follow",
        ])
        .arg(format!("--listen-unsafe={}", socket.display()))
        .arg(format!(
            "--preview={} preview {{2}}",
            shell_quote(&self_path.to_string_lossy())
        ))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn();
    let mut child = match child {
        Ok(child) => child,
        Err(error) => {
            cleanup_popup(&popup_dir, &socket);
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
        .then(|| register(config, &socket))
        .transpose()
        .ok()
        .flatten();
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
    cleanup_popup(&popup_dir, &socket);
    let selection = selection.map_err(|error| error.to_string())?;
    if let Some((pane, session)) = selection
        .split('\t')
        .nth(1)
        .zip(selection.split('\t').nth(2))
    {
        let tmux = crate::Tmux::new(config.tmux.clone());
        tmux.run(&["switch-client", "-t", session])
            .map_err(|error| error.to_string())?;
        tmux.run(&["select-pane", "-t", pane])
            .map_err(|error| error.to_string())?;
        let _ = tmux.run(&["refresh-client", "-S"]);
    }
    Ok(())
}

fn cleanup_popup(directory: &Path, socket: &Path) {
    let _ = fs::remove_file(socket);
    let _ = fs::remove_dir(directory);
}

pub fn register(config: &Config, socket: &Path) -> io::Result<PathBuf> {
    let registry = config.state_dir.join(".popups");
    secure_dir(&registry)?;
    let registration = registry.join(std::process::id().to_string());
    atomic_write(
        &registration,
        format!("{}\n{}\n", socket.display(), std::process::id()).as_bytes(),
    )?;
    Ok(registration)
}

pub fn refresh(config: &Config, executable: &Path) {
    let registry = config.state_dir.join(".popups");
    let Ok(entries) = fs::read_dir(&registry) else {
        return;
    };
    for entry in entries.flatten() {
        let registration = entry.path();
        let registered_pid = registration
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(|name| name.parse::<u32>().ok());
        if registered_pid.is_none() || is_symlink(&registration) {
            continue;
        }
        let text = fs::read_to_string(&registration).unwrap_or_default();
        let mut values = text.lines();
        let socket = values.next().map(PathBuf::from);
        let owner = values.next().and_then(|value| value.parse::<u32>().ok());
        let alive = owner.is_some_and(process_exists);
        if !alive || socket.as_ref().is_none_or(|path| !path.exists()) {
            if let Some(socket) = socket {
                let _ = fs::remove_file(socket);
            }
            let _ = fs::remove_file(registration);
            continue;
        }
        let action = format!(
            "reload({} --list)",
            shell_quote(&executable.to_string_lossy())
        );
        let _ = Command::new("curl")
            .args(["-fsS", "--unix-socket"])
            .arg(socket.expect("checked socket"))
            .args([
                "http://localhost",
                "--connect-timeout",
                "0.1",
                "--max-time",
                "0.5",
                "--data-binary",
            ])
            .arg(action)
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

#[cfg(unix)]
fn process_exists(pid: u32) -> bool {
    unsafe {
        unsafe extern "C" {
            fn kill(pid: i32, signal: i32) -> i32;
        }
        kill(pid as i32, 0) == 0
    }
}
