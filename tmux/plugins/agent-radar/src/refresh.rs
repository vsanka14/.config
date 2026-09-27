use crate::state;
use crate::{render_status, rows_excluding, session_key, Config, RowMode, Tmux};
use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::io;
use std::path::Path;
use std::process::{Command, Stdio};

pub fn refresh(config: &Config, notify: bool) -> io::Result<()> {
    refresh_excluding(config, notify, None)
}

pub(crate) fn refresh_excluding(
    config: &Config,
    notify: bool,
    excluded_pane: Option<&str>,
) -> io::Result<()> {
    let directory = config.status_dir();
    state::secure_dir(&directory)?;
    let pending = directory.join(".pending");
    let notify_pending = directory.join(".notify-pending");
    state::mark(&pending)?;
    if notify {
        state::mark(&notify_pending)?;
    }
    if let Some(pane) = excluded_pane {
        state::mark_excluded_pane(&directory, pane)?;
    }
    let lock = state::DirectoryLock::acquire(
        directory.join(".refresh.lock"),
        config.now,
        config.status_lock_stale,
    )?;
    if !lock.held() {
        return Ok(());
    }
    state::remove_file(config.cache_file());
    let mut should_notify = false;
    let mut excluded_panes = BTreeSet::new();
    while pending.exists() || notify_pending.exists() || state::has_excluded_panes(&directory)? {
        state::take_marker(&pending)?;
        should_notify |= state::take_marker(&notify_pending)?;
        excluded_panes.extend(state::take_excluded_panes(&directory)?);
        refresh_status_files(config, &directory, &excluded_panes)?;
    }
    drop(lock);
    if should_notify {
        notify_change(config);
    } else {
        let _ = Tmux::new(config.tmux.clone()).run(&["refresh-client", "-S"]);
    }
    if pending.exists() || notify_pending.exists() || state::has_excluded_panes(&directory)? {
        refresh(config, false)?;
    }
    Ok(())
}

fn refresh_status_files(
    config: &Config,
    directory: &Path,
    excluded_panes: &BTreeSet<String>,
) -> io::Result<()> {
    let tmux = Tmux::new(config.tmux.clone());
    let sessions = tmux.sessions()?;
    let fresh_rows = rows_excluding(config, RowMode::Lean, excluded_panes)?;
    for session in &sessions {
        let rendered = render_status(&config.theme, session, &sessions, &fresh_rows);
        state::atomic_write(
            &directory.join(format!("{}.txt", session_key(session))),
            rendered.as_bytes(),
        )?;
        let _ = tmux.run(&[
            "set-option",
            "-q",
            "-t",
            session,
            "@agent-radar-status",
            &rendered,
        ]);
    }
    let keep: BTreeSet<_> = sessions
        .iter()
        .map(|session| format!("{}.txt", session_key(session)))
        .collect();
    for path in state::status_files(directory)? {
        if !path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| keep.contains(name))
        {
            fs::remove_file(path)?;
        }
    }
    Ok(())
}

fn notify_change(config: &Config) {
    let _ = Tmux::new(config.tmux.clone()).run(&["refresh-client", "-S"]);
    if let Ok(executable) = env::current_exe() {
        crate::popup::refresh(config, &executable);
    }
    if env::var("AGENT_RADAR_NOTIFY").ok().as_deref() != Some("0") {
        if let Ok(command) = env::var("AGENT_RADAR_ON_CHANGE") {
            if !command.is_empty() {
                let _ = Command::new("/bin/sh")
                    .args(["-c", &command])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .spawn();
            }
        }
    }
}
