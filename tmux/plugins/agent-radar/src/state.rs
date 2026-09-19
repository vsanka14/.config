use crate::{Config, FlashKind, PaneState, Status};
use std::collections::BTreeSet;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static UNIQUE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub(crate) fn unique_sequence() -> u64 {
    UNIQUE_SEQUENCE.fetch_add(1, Ordering::Relaxed)
}

pub fn valid_pane_id(value: &str) -> bool {
    value.strip_prefix('%').is_some_and(|digits| {
        !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit())
    })
}

pub(crate) fn pane_filename(pane: &str) -> Option<String> {
    valid_pane_id(pane).then(|| format!("{}.json", &pane[1..]))
}

pub(crate) fn is_symlink(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_symlink())
        .unwrap_or(false)
}

pub(crate) fn secure_dir(path: &Path) -> io::Result<()> {
    if is_symlink(path) {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("refusing symlinked state directory: {}", path.display()),
        ));
    }
    fs::create_dir_all(path)?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
}

pub(crate) fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "state file has no parent"))?;
    secure_dir(parent)?;
    if is_symlink(path) {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            format!("refusing symlinked state file: {}", path.display()),
        ));
    }
    let mut attempts = 0;
    let (temp, mut file) = loop {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let sequence = unique_sequence();
        let temp = parent.join(format!(
            ".agent-radar-{}-{nanos}-{sequence}",
            std::process::id()
        ));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temp)
        {
            Ok(file) => break (temp, file),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists && attempts < 8 => {
                attempts += 1;
            }
            Err(error) => return Err(error),
        }
    };
    file.write_all(bytes)?;
    file.sync_all()?;
    fs::set_permissions(&temp, fs::Permissions::from_mode(0o600))?;
    fs::rename(temp, path)
}

pub fn valid_state(state: &PaneState, pane: Option<&str>, now: i64) -> bool {
    valid_pane_id(&state.pane_id)
        && pane.is_none_or(|pane| pane == state.pane_id)
        && matches!(
            state.status,
            Status::Idle | Status::Working | Status::Awaiting
        )
        && state.updated_epoch <= now + 300
}

pub fn read_state(path: &Path, pane: Option<&str>, now: i64) -> io::Result<Option<PaneState>> {
    if !path.is_file() || is_symlink(path) {
        return Ok(None);
    }
    let contents = fs::read(path)?;
    let state: PaneState = match serde_json::from_slice(&contents) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    Ok(valid_state(&state, pane, now).then_some(state))
}

pub fn write_state(config: &Config, state: &PaneState) -> io::Result<()> {
    if !valid_state(state, Some(&state.pane_id), config.now) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid pane state",
        ));
    }
    let name = pane_filename(&state.pane_id).expect("validated pane id");
    atomic_write(
        &config.state_dir.join(name),
        &serde_json::to_vec(state).expect("state serialization"),
    )
}

pub(crate) fn acknowledged(config: &Config, pane: &str) -> Option<String> {
    let path = config.state_dir.join(".ack").join(pane.strip_prefix('%')?);
    (!is_symlink(&path))
        .then(|| fs::read_to_string(path).ok())
        .flatten()
        .map(|value| value.trim().into())
}

pub fn ack_token(config: &Config, pane: &str) -> io::Result<Option<String>> {
    let Some(name) = pane_filename(pane) else {
        return Ok(None);
    };
    let Some(state) = read_state(&config.state_dir.join(name), Some(pane), config.now)? else {
        return Ok(None);
    };
    Ok((state.status == Status::Idle)
        .then_some(state.flash)
        .flatten()
        .filter(|flash| flash.kind == FlashKind::Done)
        .map(|flash| flash.id.unwrap_or_else(|| flash.until_epoch.to_string())))
}

pub fn acknowledge(config: &Config, pane: &str) -> io::Result<bool> {
    let Some(token) = ack_token(config, pane)? else {
        return Ok(false);
    };
    let directory = config.state_dir.join(".ack");
    secure_dir(&directory)?;
    let path = directory.join(&pane[1..]);
    if !is_symlink(&path)
        && fs::read_to_string(&path).ok().as_deref().map(str::trim) == Some(token.as_str())
    {
        return Ok(false);
    }
    atomic_write(&path, format!("{token}\n").as_bytes())?;
    remove_file(config.cache_file());
    Ok(true)
}

pub(crate) fn remove_pane(config: &Config, pane: &str) {
    if let Some(name) = pane_filename(pane) {
        remove_file(config.state_dir.join(name));
        remove_file(config.state_dir.join(".ack").join(&pane[1..]));
    }
}

pub(crate) fn remove_file(path: impl AsRef<Path>) {
    let _ = fs::remove_file(path);
}

pub(crate) fn read_file(path: &Path) -> io::Result<String> {
    if !path.is_file() || is_symlink(path) {
        return Err(io::Error::new(io::ErrorKind::NotFound, "file unavailable"));
    }
    fs::read_to_string(path)
}

pub(crate) fn cache_is_fresh(config: &Config, path: &Path) -> bool {
    fs::metadata(path).ok().is_some_and(|metadata| {
        let age = config.now - metadata.mtime();
        !config.now_overridden && config.cache_ttl > 0 && (0..=config.cache_ttl).contains(&age)
    })
}

pub(crate) struct DirectoryLock {
    path: PathBuf,
    held: bool,
}

impl DirectoryLock {
    pub(crate) fn acquire(path: PathBuf, now: i64, stale: i64) -> io::Result<Self> {
        if path.is_dir() && now - fs::metadata(&path)?.mtime() > stale {
            let _ = fs::remove_dir(&path);
        }
        match fs::create_dir(&path) {
            Ok(()) => Ok(Self { path, held: true }),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                Ok(Self { path, held: false })
            }
            Err(error) => Err(error),
        }
    }

    pub(crate) const fn held(&self) -> bool {
        self.held
    }
}

impl Drop for DirectoryLock {
    fn drop(&mut self) {
        if self.held {
            let _ = fs::remove_dir(&self.path);
        }
    }
}

pub(crate) fn mark(path: &Path) -> io::Result<()> {
    atomic_write(path, b"")
}

pub(crate) fn take_marker(path: &Path) -> io::Result<bool> {
    if !path.exists() {
        return Ok(false);
    }
    match fs::remove_file(path) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error),
    }
}

pub(crate) fn mark_excluded_pane(directory: &Path, pane: &str) -> io::Result<()> {
    let Some(digits) = pane.strip_prefix('%') else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid excluded pane",
        ));
    };
    mark(&directory.join(format!(".exclude-{digits}")))
}

pub(crate) fn take_excluded_panes(directory: &Path) -> io::Result<BTreeSet<String>> {
    let mut panes = BTreeSet::new();
    for entry in fs::read_dir(directory)? {
        let path = entry?.path();
        let Some(digits) = path
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(|name| name.strip_prefix(".exclude-"))
        else {
            continue;
        };
        let pane = format!("%{digits}");
        if valid_pane_id(&pane) && !is_symlink(&path) {
            panes.insert(pane);
            take_marker(&path)?;
        }
    }
    Ok(panes)
}

pub(crate) fn has_excluded_panes(directory: &Path) -> io::Result<bool> {
    Ok(fs::read_dir(directory)?
        .filter_map(Result::ok)
        .any(|entry| {
            entry
                .file_name()
                .to_str()
                .is_some_and(|name| name.starts_with(".exclude-"))
        }))
}

pub(crate) fn status_files(directory: &Path) -> io::Result<Vec<PathBuf>> {
    Ok(fs::read_dir(directory)?
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| path.extension().is_some_and(|extension| extension == "txt"))
        .collect())
}

pub(crate) fn prune(config: &Config, live_panes: &BTreeSet<String>) -> io::Result<()> {
    if !config.state_dir.is_dir() || is_symlink(&config.state_dir) {
        return Ok(());
    }
    for entry in fs::read_dir(&config.state_dir)? {
        let path = entry?.path();
        let Some(stem) = path.file_stem().and_then(|value| value.to_str()) else {
            continue;
        };
        if path
            .extension()
            .is_some_and(|extension| extension == "json")
            && !is_symlink(&path)
            && !live_panes.contains(stem)
        {
            fs::remove_file(&path)?;
            remove_file(config.state_dir.join(".ack").join(stem));
        }
    }
    Ok(())
}

pub(crate) fn migrate(config: &Config, legacy: &Path) -> io::Result<()> {
    if legacy == config.state_dir || !legacy.is_dir() || is_symlink(legacy) {
        return Ok(());
    }
    for entry in fs::read_dir(legacy)? {
        let source = entry?.path();
        if source
            .extension()
            .is_some_and(|extension| extension == "json")
            && !is_symlink(&source)
        {
            if let Some(state) = read_legacy(&source)? {
                let destination = config
                    .state_dir
                    .join(source.file_name().expect("file name"));
                if read_legacy(&destination)?
                    .is_none_or(|old| old.updated_epoch < state.updated_epoch)
                {
                    atomic_write(
                        &destination,
                        &serde_json::to_vec(&state).expect("state serialization"),
                    )?;
                }
            }
        }
    }
    Ok(())
}

fn read_legacy(path: &Path) -> io::Result<Option<PaneState>> {
    let bytes = match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error),
    };
    let state: PaneState = match serde_json::from_slice(&bytes) {
        Ok(state) => state,
        Err(_) => return Ok(None),
    };
    Ok((valid_pane_id(&state.pane_id)
        && matches!(
            state.status,
            Status::Idle | Status::Working | Status::Awaiting
        ))
    .then_some(state))
}

pub(crate) fn clean_legacy(legacy: &Path, destination: &Path) -> io::Result<()> {
    if legacy == destination
        || !legacy.ends_with("agent-status")
        || !legacy.is_dir()
        || is_symlink(legacy)
    {
        return Ok(());
    }
    for entry in fs::read_dir(legacy)? {
        let path = entry?.path();
        if is_symlink(&path) {
            continue;
        }
        if path
            .extension()
            .is_some_and(|extension| extension == "json")
            || path
                .file_name()
                .is_some_and(|name| name == ".tmux-status.cache")
            || path
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with(".tmux-status.cache."))
        {
            remove_file(path);
        } else if path
            .file_name()
            .is_some_and(|name| name == ".tmux-status.cache.lock")
            && path.is_dir()
        {
            let _ = fs::remove_dir(path);
        } else if path.file_name().is_some_and(|name| name == ".status") && path.is_dir() {
            for child in fs::read_dir(&path)? {
                let child = child?.path();
                if is_symlink(&child) {
                    continue;
                }
                let name = child
                    .file_name()
                    .and_then(|value| value.to_str())
                    .unwrap_or_default();
                if child
                    .extension()
                    .is_some_and(|extension| extension == "txt")
                    || matches!(name, ".stamp" | ".pending" | ".notify-pending")
                    || name.starts_with(".exclude-")
                {
                    remove_file(child);
                } else if name == ".refresh.lock" && child.is_dir() {
                    let _ = fs::remove_dir(child);
                }
            }
            let _ = fs::remove_dir(path);
        }
    }
    let _ = fs::remove_dir(legacy);
    Ok(())
}

pub(crate) fn permissions_are_secure(path: &Path) -> bool {
    !path.exists()
        || (path.is_dir()
            && !is_symlink(path)
            && fs::metadata(path)
                .map(|metadata| metadata.permissions().mode() & 0o777 == 0o700)
                .unwrap_or(false))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_only_safe_panes() {
        assert!(valid_pane_id("%123"));
        assert!(!valid_pane_id("%a"));
    }
}
