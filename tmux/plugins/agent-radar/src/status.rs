use crate::state;
use crate::{render_status, rows, rows_text, Config, PaneRow, RowMode, Status, Tmux};
use std::fs;
use std::io;

pub(crate) fn cached_lean_rows(config: &Config) -> io::Result<Vec<PaneRow>> {
    if config.now_overridden {
        return rows(config, RowMode::Lean);
    }
    let cache = config.cache_file();
    let text = if state::cache_is_fresh(config, &cache) && !state::is_symlink(&cache) {
        fs::read_to_string(&cache)?
    } else {
        state::secure_dir(&config.state_dir)?;
        let lock = state::DirectoryLock::acquire(
            cache.with_extension("cache.lock"),
            config.now,
            config.cache_lock_stale,
        )?;
        if lock.held() {
            let output = rows_text(config, RowMode::Lean, false)?;
            state::atomic_write(&cache, output.as_bytes())?;
            output
        } else if cache.is_file() && !state::is_symlink(&cache) {
            fs::read_to_string(&cache)?
        } else {
            rows_text(config, RowMode::Lean, false)?
        }
    };
    Ok(text.lines().filter_map(parse_lean_row).collect())
}

fn parse_lean_row(line: &str) -> Option<PaneRow> {
    let values: Vec<_> = line.splitn(4, '\t').collect();
    let rank: u8 = values.first()?.parse().ok()?;
    let (session, target) = (values.get(2)?.to_string(), values.get(3)?.to_string());
    let (_, location) = target.split_once(':')?;
    let (window, index) = location.split_once('.')?;
    Some(PaneRow {
        pane_id: values.get(1)?.to_string(),
        session,
        window_index: window.into(),
        pane_index: index.into(),
        title: String::new(),
        status: match rank {
            1 => Status::Awaiting,
            2 => Status::Working,
            3 => Status::Done,
            4 => Status::Idle,
            _ => Status::Unknown,
        },
    })
}

pub fn session_key(session: &str) -> String {
    session
        .as_bytes()
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect()
}

pub fn status(config: &Config, current: &str) -> io::Result<String> {
    let tmux = Tmux::new(config.tmux.clone());
    let sessions = tmux.sessions()?;
    let rows = cached_lean_rows(config)?;
    Ok(render_status(&config.theme, current, &sessions, &rows))
}

pub fn cached_status(config: &Config, session: &str) -> io::Result<String> {
    let path = config
        .status_dir()
        .join(format!("{}.txt", session_key(session)));
    match state::read_file(&path) {
        Ok(contents) => Ok(contents),
        Err(error) if error.kind() == io::ErrorKind::NotFound => status(config, session),
        Err(error) => Err(error),
    }
}
