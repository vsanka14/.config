mod config;
mod hooks;
mod model;
mod notify;
mod popup;
mod refresh;
mod render;
mod scan;
mod setup;
mod state;
mod status;
mod tmux;

pub use config::{epoch_now, Config, RadarConfig};
pub use hooks::{
    fold_hook_event, format_iso_utc, hook, limit_metadata, sanitize_session_id, FlashAction,
    HookDetails, HookEvent, HookTransition,
};
pub use model::{Flash, FlashKind, PaneRow, PaneState, SessionPriority, Status, StatusRank};
pub use notify::{notification_records, notification_text, NotificationRecord};
pub use refresh::refresh;
pub use render::{
    badge_color, clean_field, clean_title, format_display_row, pill_cell, radar_label,
    status_label, truncate_utf8_bytes, COPILOT_TITLE_SUFFIX,
};
pub use scan::{effective_status, rows, rows_text, RowMode};
pub use setup::{descriptor, doctor, doctor_default, install, install_default};
pub use state::{ack_token, acknowledge, read_state, valid_pane_id, valid_state, write_state};
pub use status::{cached_status, session_key, status};
pub use tmux::{copilot_pane_pids, parse_panes, parse_process_snapshot, Process, Tmux, TmuxPane};

pub(crate) use config::env_path;
pub(crate) use render::render_status;
pub(crate) use scan::rows_excluding;

use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn open_popup(config: &Config) -> Result<(), String> {
    popup::open(config)
}

pub fn preview(config: &Config, pane: &str) -> Result<String, String> {
    let output = Command::new(&config.tmux)
        .args(["capture-pane", "-p", "-e", "-t", pane, "-S", "-20"])
        .output()
        .map_err(|error| error.to_string())?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).into_owned())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).into_owned())
    }
}

pub fn register_popup(config: &Config, socket: &Path) -> io::Result<PathBuf> {
    popup::register(config, socket)
}

pub fn refresh_popups(config: &Config, executable: &Path) {
    popup::refresh(config, executable);
}

pub mod boundary {
    pub use super::{
        ack_token, acknowledge, cached_status, copilot_pane_pids, descriptor, doctor,
        doctor_default, hook, install, install_default, notification_text, open_popup, parse_panes,
        parse_process_snapshot, preview, read_state, refresh, refresh_popups, register_popup, rows,
        rows_text, session_key, status, valid_pane_id, valid_state, write_state, Config, Process,
        RowMode, Tmux, TmuxPane,
    };
}
