//! Pure, deterministic behavior for Agent Radar.
//!
//! System integration (tmux, filesystem state, hooks, fzf, and setup) remains
//! deliberately outside this crate's implemented surface until its parity work
//! is complete.

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};

pub const COPILOT_TITLE_SUFFIX: &str = " - GitHub Copilot";

#[derive(Clone, Copy, Debug, Default, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Awaiting,
    Working,
    Done,
    Idle,
    #[default]
    Unknown,
    Removed,
}

impl Status {
    pub const fn rank(self) -> Option<StatusRank> {
        match self {
            Self::Awaiting => Some(StatusRank::Awaiting),
            Self::Working => Some(StatusRank::Working),
            Self::Done => Some(StatusRank::Done),
            Self::Idle => Some(StatusRank::Idle),
            Self::Unknown => Some(StatusRank::Unknown),
            Self::Removed => None,
        }
    }

    pub const fn label(self) -> &'static str {
        match self {
            Self::Awaiting => "⏸ awaiting",
            Self::Working => "⚙ working",
            Self::Done => "✓ done",
            Self::Idle => "✓ idle",
            Self::Unknown | Self::Removed => "? unknown",
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Awaiting => "awaiting",
            Self::Working => "working",
            Self::Done => "done",
            Self::Idle => "idle",
            Self::Unknown => "unknown",
            Self::Removed => "removed",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[repr(u8)]
pub enum StatusRank {
    Awaiting = 1,
    Working = 2,
    Done = 3,
    Idle = 4,
    Unknown = 5,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SessionPriority {
    Awaiting,
    Done,
    Other,
}

impl SessionPriority {
    pub const fn from_status(status: Status) -> Self {
        match status {
            Status::Awaiting => Self::Awaiting,
            Status::Done => Self::Done,
            _ => Self::Other,
        }
    }
}

impl Ord for SessionPriority {
    fn cmp(&self, other: &Self) -> Ordering {
        self.as_u8().cmp(&other.as_u8())
    }
}

impl PartialOrd for SessionPriority {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl SessionPriority {
    const fn as_u8(self) -> u8 {
        match self {
            Self::Awaiting => 0,
            Self::Done => 1,
            Self::Other => 2,
        }
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HookDetails {
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub subagent_name: Option<String>,
    #[serde(default)]
    pub notification_type: Option<String>,
    #[serde(default)]
    pub recoverable: Option<bool>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HookEvent {
    SessionStart,
    UserPromptSubmitted,
    PermissionRequest,
    PreToolUse,
    PostToolUse,
    PostToolUseFailure,
    Notification,
    ErrorOccurred,
    Abort,
    AgentStop,
    SubagentStart,
    SubagentStop,
    SessionEnd,
}

impl HookDetails {
    pub fn sanitized(self) -> Self {
        Self {
            tool_name: self.tool_name.map(|value| limit_metadata(&value)),
            subagent_name: self.subagent_name.map(|value| limit_metadata(&value)),
            notification_type: self.notification_type,
            recoverable: self.recoverable,
        }
    }
}

impl HookEvent {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "sessionStart" => Some(Self::SessionStart),
            "userPromptSubmitted" => Some(Self::UserPromptSubmitted),
            "permissionRequest" => Some(Self::PermissionRequest),
            "preToolUse" => Some(Self::PreToolUse),
            "postToolUse" => Some(Self::PostToolUse),
            "postToolUseFailure" => Some(Self::PostToolUseFailure),
            "notification" => Some(Self::Notification),
            "errorOccurred" => Some(Self::ErrorOccurred),
            "abort" => Some(Self::Abort),
            "agentStop" => Some(Self::AgentStop),
            "subagentStart" => Some(Self::SubagentStart),
            "subagentStop" => Some(Self::SubagentStop),
            "sessionEnd" => Some(Self::SessionEnd),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FlashAction {
    Clear,
    CreateDone,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct HookTransition {
    pub status: Status,
    pub flash: FlashAction,
}

pub fn fold_hook_event(
    previous: Status,
    event: HookEvent,
    details: &HookDetails,
) -> Option<HookTransition> {
    let status = match event {
        // Copilot can deliver a delayed sessionStart after work has begun. The
        // shell hook leaves the existing state file untouched in that case.
        HookEvent::SessionStart if matches!(previous, Status::Working | Status::Awaiting) => {
            return None
        }
        HookEvent::SessionStart => Status::Idle,
        HookEvent::UserPromptSubmitted
        | HookEvent::PermissionRequest
        | HookEvent::PostToolUse
        | HookEvent::PostToolUseFailure
        | HookEvent::SubagentStart
        | HookEvent::SubagentStop => Status::Working,
        HookEvent::PreToolUse => match details.tool_name.as_deref() {
            Some("ask_user" | "AskUserQuestion" | "exit_plan_mode") => Status::Awaiting,
            _ => Status::Working,
        },
        HookEvent::Notification => match details.notification_type.as_deref() {
            Some("permission_prompt" | "elicitation_dialog") => Status::Awaiting,
            _ => return None,
        },
        HookEvent::ErrorOccurred => {
            if details.recoverable == Some(true) {
                Status::Working
            } else {
                Status::Idle
            }
        }
        HookEvent::Abort | HookEvent::AgentStop => Status::Idle,
        HookEvent::SessionEnd => Status::Removed,
    };
    let flash = if event == HookEvent::AgentStop && previous == Status::Working {
        FlashAction::CreateDone
    } else {
        FlashAction::Clear
    };
    Some(HookTransition { status, flash })
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct Flash {
    pub kind: FlashKind,
    pub until_epoch: i64,
    #[serde(default)]
    pub id: Option<String>,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FlashKind {
    Done,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PaneState {
    pub pane_id: String,
    #[serde(default = "unknown_session_id")]
    pub session_id: String,
    #[serde(default)]
    pub process_pid: u32,
    pub status: Status,
    #[serde(default)]
    pub event: String,
    #[serde(default)]
    pub updated_at: String,
    pub updated_epoch: i64,
    #[serde(default)]
    pub tool_name: Option<String>,
    #[serde(default)]
    pub subagent_name: Option<String>,
    #[serde(default)]
    pub flash: Option<Flash>,
}

fn unknown_session_id() -> String {
    "unknown".into()
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PaneRow {
    pub pane_id: String,
    pub session: String,
    pub window_index: String,
    pub pane_index: String,
    pub title: String,
    pub status: Status,
}

impl PaneRow {
    pub fn target(&self) -> String {
        format!(
            "{}:{}.{}",
            clean_field(&self.session),
            self.window_index,
            self.pane_index
        )
    }

    pub fn full_tsv(&self, color: bool) -> String {
        let title = clean_title(&self.title);
        format!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}",
            self.status.rank().map(|rank| rank as u8).unwrap_or(5),
            self.pane_id,
            clean_field(&self.session),
            self.target(),
            status_label(self.status, color),
            title,
            format_display_row(self.status, &self.target(), &title, color)
        )
    }

    pub fn lean_tsv(&self) -> String {
        format!(
            "{}\t{}\t{}\t{}",
            self.status.rank().map(|rank| rank as u8).unwrap_or(5),
            self.pane_id,
            clean_field(&self.session),
            self.target()
        )
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct RadarConfig {
    pub color_awaiting: String,
    pub color_working: String,
    pub color_done: String,
    pub color_idle: String,
    pub color_accent: String,
    pub color_muted: String,
    pub color_dim: String,
    pub color_pill_bg: String,
    pub color_status_bg: String,
    #[serde(default)]
    pub radar_numbers: bool,
}

impl Default for RadarConfig {
    fn default() -> Self {
        Self {
            color_awaiting: "#f7768e".into(),
            color_working: "#e0af68".into(),
            color_done: "#3fb950".into(),
            color_idle: "#9ece6a".into(),
            color_accent: "#7dcfff".into(),
            color_muted: "#565f89".into(),
            color_dim: "#414868".into(),
            color_pill_bg: "#24283b".into(),
            color_status_bg: "#050505".into(),
            radar_numbers: false,
        }
    }
}

pub fn clean_field(value: &str) -> String {
    value.replace(['\t', '\r', '\n'], " ")
}

pub fn sanitize_session_id(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
        .collect()
}

pub fn limit_metadata(value: &str) -> String {
    truncate_utf8_bytes(value, 120).into()
}

pub fn clean_title(value: &str) -> String {
    let title = clean_field(value);
    let title = title.split(COPILOT_TITLE_SUFFIX).next().unwrap_or_default();
    if title.is_empty() || title == "GitHub Copilot" {
        "-".into()
    } else {
        title.into()
    }
}

pub fn status_label(status: Status, color: bool) -> String {
    let label = status.label();
    if !color {
        return label.into();
    }
    format!("\x1b[38;2;{}m{}\x1b[0m", rgb(status), label)
}

pub fn format_display_row(status: Status, target: &str, title: &str, color: bool) -> String {
    let status_cell = format!("{:<10}", status.as_str());
    let target_cell = pad_right_bytes(truncate_utf8_bytes(target, 26), 26);
    if !color {
        return format!("{status_cell}  {target_cell}  {title}");
    }
    format!(
        "\x1b[38;2;{}m{}\x1b[0m  \x1b[38;2;122;162;247m{}\x1b[0m  {}",
        rgb(status),
        status_cell,
        target_cell,
        title
    )
}

pub fn pill_cell(status: Status, pane_target: &str, config: &RadarConfig) -> String {
    match status {
        Status::Awaiting => format!("#[fg={},bold]{} ", config.color_awaiting, pane_target),
        Status::Working => format!("#[fg={},bold]{} ", config.color_working, pane_target),
        Status::Done => format!("#[fg={},bold]✓{} ", config.color_done, pane_target),
        Status::Idle => format!("#[fg={},nobold]{} ", config.color_idle, pane_target),
        Status::Unknown | Status::Removed => {
            format!("#[fg={},nobold]{} ", config.color_muted, pane_target)
        }
    }
}

pub fn dot_color(priority: SessionPriority, is_current: bool, config: &RadarConfig) -> &str {
    match priority {
        SessionPriority::Awaiting => &config.color_awaiting,
        SessionPriority::Done => &config.color_done,
        SessionPriority::Other if is_current => &config.color_idle,
        SessionPriority::Other => &config.color_muted,
    }
}

pub fn radar_glyph(position: usize, is_current: bool, numbered: bool) -> &'static str {
    const NUMBERED: [&str; 10] = [
        "\u{f0ca0}",
        "\u{f0ca2}",
        "\u{f0ca4}",
        "\u{f0ca6}",
        "\u{f0ca8}",
        "\u{f0caa}",
        "\u{f0cac}",
        "\u{f0cae}",
        "\u{f0cb0}",
        "\u{f0fec}",
    ];
    if numbered && (1..=10).contains(&position) {
        NUMBERED[position - 1]
    } else if is_current {
        "◉"
    } else {
        "●"
    }
}

pub fn effective_status(
    state: &PaneState,
    now: i64,
    acknowledged_flash_id: Option<&str>,
    notifications: bool,
) -> Status {
    let Some(flash) = &state.flash else {
        return state.status;
    };
    if state.status != Status::Idle || flash.kind != FlashKind::Done {
        return state.status;
    }
    let flash_id = flash
        .id
        .as_deref()
        .map(str::to_owned)
        .unwrap_or_else(|| flash.until_epoch.to_string());
    if acknowledged_flash_id == Some(flash_id.as_str()) {
        return Status::Idle;
    }
    if !notifications || flash.until_epoch > now {
        Status::Done
    } else {
        Status::Idle
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NotificationRecord {
    Color(String),
    Line { session: String, kind: Status },
}

/// Emits notable sessions in supplied creation order. Notable sessions not in
/// that list follow in stable lexical session-name order.
pub fn notification_records(
    session_order: &[String],
    rows: &[PaneRow],
    config: &RadarConfig,
) -> Vec<NotificationRecord> {
    if rows.is_empty() {
        return Vec::new();
    }
    let mut best = BTreeMap::<&str, SessionPriority>::new();
    for row in rows {
        best.entry(&row.session)
            .and_modify(|priority| {
                *priority = (*priority).min(SessionPriority::from_status(row.status))
            })
            .or_insert_with(|| SessionPriority::from_status(row.status));
    }
    let global = best
        .values()
        .copied()
        .min()
        .unwrap_or(SessionPriority::Other);
    let color = match global {
        SessionPriority::Awaiting => &config.color_awaiting,
        SessionPriority::Done => &config.color_done,
        SessionPriority::Other => &config.color_accent,
    };
    let mut records = vec![NotificationRecord::Color(color.clone())];
    let mut emitted = BTreeSet::new();
    for session in session_order {
        if let Some(priority @ (SessionPriority::Awaiting | SessionPriority::Done)) =
            best.get(session.as_str())
        {
            records.push(NotificationRecord::Line {
                session: session.clone(),
                kind: if *priority == SessionPriority::Awaiting {
                    Status::Awaiting
                } else {
                    Status::Done
                },
            });
            emitted.insert(session.as_str());
        }
    }
    for (session, priority) in best {
        if !emitted.contains(session)
            && matches!(priority, SessionPriority::Awaiting | SessionPriority::Done)
        {
            records.push(NotificationRecord::Line {
                session: session.into(),
                kind: if priority == SessionPriority::Awaiting {
                    Status::Awaiting
                } else {
                    Status::Done
                },
            });
        }
    }
    records
}

fn rgb(status: Status) -> &'static str {
    match status {
        Status::Awaiting => "247;118;142",
        Status::Working => "224;175;104",
        Status::Done => "63;185;80",
        Status::Idle => "158;206;106",
        Status::Unknown | Status::Removed => "86;95;137",
    }
}

/// Matches a shell printf byte precision without producing invalid UTF-8.
pub fn truncate_utf8_bytes(value: &str, limit: usize) -> &str {
    if value.len() <= limit {
        return value;
    }
    let end = value
        .char_indices()
        .take_while(|(index, _)| *index <= limit)
        .map(|(index, _)| index)
        .last()
        .unwrap_or(0);
    &value[..end]
}

fn pad_right_bytes(value: &str, width: usize) -> String {
    format!("{value}{}", " ".repeat(width.saturating_sub(value.len())))
}

pub mod boundary {
    use super::*;

    #[test]
    fn maps_copilot_events_and_flash_actions() {
        let awaiting = HookDetails {
            tool_name: Some("ask_user".into()),
            ..Default::default()
        };
        assert_eq!(
            fold_hook_event(Status::Idle, HookEvent::PreToolUse, &awaiting),
            Some(HookTransition {
                status: Status::Awaiting,
                flash: FlashAction::Clear
            })
        );
        assert_eq!(
            fold_hook_event(
                Status::Working,
                HookEvent::AgentStop,
                &HookDetails::default()
            ),
            Some(HookTransition {
                status: Status::Idle,
                flash: FlashAction::CreateDone
            })
        );
        assert_eq!(
            fold_hook_event(
                Status::Awaiting,
                HookEvent::Notification,
                &HookDetails::default()
            ),
            None
        );
        assert_eq!(
            fold_hook_event(
                Status::Working,
                HookEvent::SessionStart,
                &HookDetails::default()
            ),
            None
        );
        assert_eq!(
            fold_hook_event(
                Status::Awaiting,
                HookEvent::SessionStart,
                &HookDetails::default()
            ),
            None
        );
        assert_eq!(
            fold_hook_event(
                Status::Idle,
                HookEvent::SessionStart,
                &HookDetails::default()
            ),
            Some(HookTransition {
                status: Status::Idle,
                flash: FlashAction::Clear
            })
        );
        let visible_notification = HookDetails {
            notification_type: Some("permission_prompt".into()),
            ..Default::default()
        };
        assert_eq!(
            fold_hook_event(Status::Idle, HookEvent::Notification, &visible_notification),
            Some(HookTransition {
                status: Status::Awaiting,
                flash: FlashAction::Clear
            })
        );
    }

    // The remaining types are intentionally std-only boundary adapters.  Keeping
    // command invocation and state ownership here makes the CLI a thin dispatcher.
    mod implementation {
        use super::*;
        use serde_json::{json, Value};
        use std::env;
        use std::fs::{self, OpenOptions};
        use std::io::{self, Read, Write};
        use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
        use std::path::{Path, PathBuf};
        use std::process::{Command, Stdio};
        use std::sync::atomic::{AtomicU64, Ordering as AtomicOrdering};
        use std::time::{SystemTime, UNIX_EPOCH};

        pub const MAX_ANCESTRY: usize = 256;
        static UNIQUE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

        #[derive(Clone, Debug)]
        pub struct Config {
            pub state_dir: PathBuf,
            pub tmux: String,
            pub now: i64,
            pub now_overridden: bool,
            pub cache_ttl: i64,
            pub done_ttl: i64,
            pub status_lock_stale: i64,
            pub cache_lock_stale: i64,
            pub process_snapshot: Option<PathBuf>,
            pub config: RadarConfig,
        }

        impl Config {
            pub fn from_env() -> Self {
                let state_dir = env_path("AGENT_RADAR_STATE_DIR")
                    .or_else(|| env_path("TMUX_AGENT_ENGINE_STATE_DIR"))
                    .unwrap_or_else(|| {
                        PathBuf::from(env::var("XDG_STATE_HOME").unwrap_or_else(|_| {
                            format!("{}/.local/state", env::var("HOME").unwrap_or_default())
                        }))
                        .join("agent-radar")
                    });
                let overridden = env::var_os("TMUX_AGENT_ENGINE_NOW").is_some();
                let now = env_i64("TMUX_AGENT_ENGINE_NOW").unwrap_or_else(epoch_now);
                let mut colors = RadarConfig::default();
                set_color(&mut colors.color_awaiting, "AGENT_RADAR_COLOR_AWAITING");
                set_color(&mut colors.color_working, "AGENT_RADAR_COLOR_WORKING");
                set_color(&mut colors.color_done, "AGENT_RADAR_COLOR_DONE");
                set_color(&mut colors.color_idle, "AGENT_RADAR_COLOR_IDLE");
                set_color(&mut colors.color_accent, "AGENT_RADAR_COLOR_ACCENT");
                set_color(&mut colors.color_muted, "AGENT_RADAR_COLOR_MUTED");
                set_color(&mut colors.color_dim, "AGENT_RADAR_COLOR_DIM");
                set_color(&mut colors.color_pill_bg, "AGENT_RADAR_COLOR_PILL_BG");
                set_color(&mut colors.color_status_bg, "AGENT_RADAR_COLOR_STATUS_BG");
                Self {
                    state_dir,
                    tmux: env::var("AGENT_RADAR_TMUX_BIN")
                        .or_else(|_| env::var("TMUX_AGENT_ENGINE_TMUX_BIN"))
                        .unwrap_or_else(|_| "tmux".into()),
                    now,
                    now_overridden: overridden,
                    cache_ttl: env_i64("AGENT_RADAR_CACHE_TTL")
                        .or_else(|| env_i64("TMUX_AGENT_ENGINE_CACHE_TTL"))
                        .unwrap_or(2),
                    done_ttl: env_i64("AGENT_RADAR_DONE_TTL")
                        .or_else(|| env_i64("TMUX_AGENT_STATUS_DONE_TTL"))
                        .unwrap_or(3),
                    status_lock_stale: env_i64("TMUX_AGENT_ENGINE_STATUS_LOCK_STALE").unwrap_or(30),
                    cache_lock_stale: env_i64("TMUX_AGENT_ENGINE_CACHE_LOCK_STALE").unwrap_or(30),
                    process_snapshot: env_path("TMUX_AGENT_ENGINE_PS_FILE"),
                    config: colors,
                }
            }
            pub fn cache_file(&self) -> PathBuf {
                env_path("TMUX_AGENT_ENGINE_CACHE_FILE")
                    .unwrap_or_else(|| self.state_dir.join(".tmux-status.cache"))
            }
            pub fn status_dir(&self) -> PathBuf {
                env_path("TMUX_AGENT_ENGINE_STATUS_DIR")
                    .unwrap_or_else(|| self.state_dir.join(".status"))
            }
        }

        fn env_path(name: &str) -> Option<PathBuf> {
            env::var_os(name)
                .filter(|v| !v.is_empty())
                .map(PathBuf::from)
        }
        fn env_i64(name: &str) -> Option<i64> {
            env::var(name).ok()?.parse().ok()
        }
        fn set_color(destination: &mut String, name: &str) {
            if let Ok(value) = env::var(name) {
                *destination = value;
            }
        }
        pub fn epoch_now() -> i64 {
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64
        }

        pub fn valid_pane_id(value: &str) -> bool {
            value.strip_prefix('%').is_some_and(|digits| {
                !digits.is_empty() && digits.bytes().all(|b| b.is_ascii_digit())
            })
        }
        fn pane_filename(pane: &str) -> Option<String> {
            valid_pane_id(pane).then(|| format!("{}.json", &pane[1..]))
        }
        fn is_symlink(path: &Path) -> bool {
            fs::symlink_metadata(path)
                .map(|m| m.file_type().is_symlink())
                .unwrap_or(false)
        }
        fn secure_dir(path: &Path) -> io::Result<()> {
            if is_symlink(path) {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    format!("refusing symlinked state directory: {}", path.display()),
                ));
            }
            fs::create_dir_all(path)?;
            fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        }
        fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
            let parent = path.parent().ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidInput, "state file has no parent")
            })?;
            secure_dir(parent)?;
            if is_symlink(path) {
                return Err(io::Error::new(
                    io::ErrorKind::PermissionDenied,
                    format!("refusing symlinked state file: {}", path.display()),
                ));
            }
            let mut attempts = 0;
            let mut temp;
            let mut file;
            loop {
                let nanos = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos();
                let sequence = UNIQUE_SEQUENCE.fetch_add(1, AtomicOrdering::Relaxed);
                temp = parent.join(format!(
                    ".agent-radar-{}-{nanos}-{sequence}",
                    std::process::id()
                ));
                match OpenOptions::new()
                    .write(true)
                    .create_new(true)
                    .mode(0o600)
                    .open(&temp)
                {
                    Ok(opened) => {
                        file = opened;
                        break;
                    }
                    Err(error) if error.kind() == io::ErrorKind::AlreadyExists && attempts < 8 => {
                        attempts += 1
                    }
                    Err(error) => return Err(error),
                }
            }
            file.write_all(bytes)?;
            file.sync_all()?;
            fs::set_permissions(&temp, fs::Permissions::from_mode(0o600))?;
            fs::rename(&temp, path)
        }

        pub fn valid_state(state: &PaneState, pane: Option<&str>, now: i64) -> bool {
            valid_pane_id(&state.pane_id)
                && pane.map_or(true, |p| p == state.pane_id)
                && matches!(
                    state.status,
                    Status::Idle | Status::Working | Status::Awaiting
                )
                && state.updated_epoch <= now + 300
        }
        pub fn read_state(
            path: &Path,
            pane: Option<&str>,
            now: i64,
        ) -> io::Result<Option<PaneState>> {
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
            let name = pane_filename(&state.pane_id).unwrap();
            atomic_write(
                &config.state_dir.join(name),
                &serde_json::to_vec(state).expect("state serialization"),
            )
        }
        pub fn ack_token(config: &Config, pane: &str) -> io::Result<Option<String>> {
            let Some(name) = pane_filename(pane) else {
                return Ok(None);
            };
            let Some(state) = read_state(&config.state_dir.join(name), Some(pane), config.now)?
            else {
                return Ok(None);
            };
            Ok((state.status == Status::Idle)
                .then(|| state.flash)
                .flatten()
                .filter(|flash| flash.kind == FlashKind::Done)
                .map(|flash| flash.id.unwrap_or_else(|| flash.until_epoch.to_string())))
        }
        pub fn acknowledge(config: &Config, pane: &str) -> io::Result<bool> {
            let Some(token) = ack_token(config, pane)? else {
                return Ok(false);
            };
            let dir = config.state_dir.join(".ack");
            secure_dir(&dir)?;
            let path = dir.join(&pane[1..]);
            if !is_symlink(&path)
                && fs::read_to_string(&path).ok().as_deref().map(str::trim) == Some(token.as_str())
            {
                return Ok(false);
            }
            atomic_write(&path, format!("{token}\n").as_bytes())?;
            let _ = fs::remove_file(config.cache_file());
            Ok(true)
        }

        #[derive(Clone, Debug, Eq, PartialEq)]
        pub struct Process {
            pub pid: u32,
            pub parent: u32,
            pub command: String,
        }
        pub fn parse_process_snapshot(input: &str) -> Vec<Process> {
            input
                .lines()
                .filter_map(|line| {
                    let mut fields = line.split_whitespace();
                    Some(Process {
                        pid: fields.next()?.parse().ok()?,
                        parent: fields.next()?.parse().ok()?,
                        command: fields.next()?.into(),
                    })
                })
                .collect()
        }
        pub fn copilot_pane_pids(panes: &[TmuxPane], processes: &[Process]) -> BTreeSet<u32> {
            let parent: BTreeMap<u32, u32> = processes.iter().map(|p| (p.pid, p.parent)).collect();
            let roots: BTreeMap<u32, u32> = panes.iter().map(|p| (p.pid, p.pid)).collect();
            let mut found = BTreeSet::new();
            for process in processes.iter().filter(|p| {
                Path::new(&p.command)
                    .file_name()
                    .is_some_and(|name| name == "copilot")
            }) {
                let mut current = process.pid;
                for _ in 0..MAX_ANCESTRY {
                    if let Some(root) = roots.get(&current) {
                        found.insert(*root);
                        break;
                    }
                    let Some(next) = parent.get(&current) else {
                        break;
                    };
                    if *next == 0 || *next == current {
                        break;
                    }
                    current = *next;
                }
            }
            found
        }

        #[derive(Clone, Debug, Eq, PartialEq)]
        pub struct TmuxPane {
            pub pane_id: String,
            pub session: String,
            pub window: String,
            pub index: String,
            pub pid: u32,
            pub title: String,
        }
        pub fn parse_panes(input: &str) -> Vec<TmuxPane> {
            input
                .lines()
                .filter_map(|line| {
                    let values: Vec<_> = line.splitn(6, '\t').collect();
                    if values.len() != 6 || !valid_pane_id(values[0]) {
                        return None;
                    }
                    Some(TmuxPane {
                        pane_id: values[0].into(),
                        session: values[1].into(),
                        window: values[2].into(),
                        index: values[3].into(),
                        pid: values[4].parse().ok()?,
                        title: values[5].into(),
                    })
                })
                .collect()
        }

        #[derive(Clone, Debug)]
        pub struct Tmux {
            bin: String,
        }
        impl Tmux {
            pub fn new(bin: String) -> Self {
                Self { bin }
            }
            pub fn output(&self, args: &[&str]) -> io::Result<String> {
                let output = Command::new(&self.bin).args(args).output()?;
                if output.status.success() {
                    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
                } else {
                    Err(io::Error::new(
                        io::ErrorKind::Other,
                        String::from_utf8_lossy(&output.stderr).into_owned(),
                    ))
                }
            }
            pub fn run(&self, args: &[&str]) -> io::Result<()> {
                self.output(args).map(|_| ())
            }
            pub fn panes(&self) -> io::Result<Vec<TmuxPane>> {
                Ok(parse_panes(&self.output(&["list-panes", "-a", "-F", "#{pane_id}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}\t#{pane_title}"])?))
            }
            pub fn pane_roots(&self) -> io::Result<BTreeMap<u32, String>> {
                Ok(self
                    .output(&["list-panes", "-a", "-F", "#{pane_id}\t#{pane_pid}"])?
                    .lines()
                    .filter_map(|line| {
                        let (pane, pid) = line.split_once('\t')?;
                        valid_pane_id(pane)
                            .then(|| pid.parse::<u32>().ok().map(|pid| (pid, pane.to_owned())))
                            .flatten()
                    })
                    .collect())
            }
            pub fn sessions(&self) -> io::Result<Vec<String>> {
                let mut rows: Vec<(i64, String)> = self
                    .output(&["list-sessions", "-F", "#{session_created}\t#{session_name}"])?
                    .lines()
                    .filter_map(|line| {
                        let (time, name) = line.split_once('\t')?;
                        Some((time.parse().ok()?, name.into()))
                    })
                    .collect();
                rows.sort();
                Ok(rows.into_iter().map(|(_, name)| name).collect())
            }
        }
        fn snapshot(config: &Config) -> io::Result<Vec<Process>> {
            let text = match &config.process_snapshot {
                Some(path) => fs::read_to_string(path)?,
                None => {
                    let output = Command::new("ps")
                        .args(["-axo", "pid=,ppid=,comm="])
                        .output()?;
                    if !output.status.success() {
                        return Err(io::Error::new(
                            io::ErrorKind::Other,
                            String::from_utf8_lossy(&output.stderr).into_owned(),
                        ));
                    }
                    String::from_utf8_lossy(&output.stdout).into_owned()
                }
            };
            Ok(parse_process_snapshot(&text))
        }
        fn acknowledged(config: &Config, pane: &str) -> Option<String> {
            let path = config.state_dir.join(".ack").join(pane.strip_prefix('%')?);
            (!is_symlink(&path))
                .then(|| fs::read_to_string(path).ok())
                .flatten()
                .map(|x| x.trim().into())
        }
        pub fn rows(config: &Config, mode: &str) -> io::Result<Vec<PaneRow>> {
            let tmux = Tmux::new(config.tmux.clone());
            let panes = tmux.panes()?;
            let live = copilot_pane_pids(&panes, &snapshot(config)?);
            let mut result = Vec::new();
            for pane in panes.iter().filter(|p| live.contains(&p.pid)) {
                let state = read_state(
                    &config
                        .state_dir
                        .join(format!("{}.json", &pane.pane_id[1..])),
                    Some(&pane.pane_id),
                    config.now,
                )?;
                let status = state
                    .as_ref()
                    .map(|state| {
                        effective_status(
                            state,
                            config.now,
                            acknowledged(config, &pane.pane_id).as_deref(),
                            mode == "notify",
                        )
                    })
                    .unwrap_or(Status::Unknown);
                result.push(PaneRow {
                    pane_id: pane.pane_id.clone(),
                    session: clean_field(&pane.session),
                    window_index: pane.window.clone(),
                    pane_index: pane.index.clone(),
                    title: pane.title.clone(),
                    status,
                });
            }
            prune(config, &panes)?;
            result.sort_by(|a, b| {
                (
                    a.status.rank().map(|x| x as u8).unwrap_or(5),
                    &a.session,
                    a.target(),
                )
                    .cmp(&(
                        b.status.rank().map(|x| x as u8).unwrap_or(5),
                        &b.session,
                        b.target(),
                    ))
            });
            Ok(result)
        }
        fn prune(config: &Config, panes: &[TmuxPane]) -> io::Result<()> {
            if !config.state_dir.is_dir() || is_symlink(&config.state_dir) {
                return Ok(());
            }
            let live: BTreeSet<_> = panes
                .iter()
                .map(|p| p.pane_id.strip_prefix('%').unwrap_or("").to_owned())
                .collect();
            for entry in fs::read_dir(&config.state_dir)? {
                let entry = entry?;
                let path = entry.path();
                let Some(stem) = path.file_stem().and_then(|x| x.to_str()) else {
                    continue;
                };
                if path.extension().is_some_and(|x| x == "json")
                    && !is_symlink(&path)
                    && !live.contains(stem)
                {
                    fs::remove_file(&path)?;
                    let _ = fs::remove_file(config.state_dir.join(".ack").join(stem));
                }
            }
            Ok(())
        }
        pub fn rows_text(config: &Config, mode: &str, color: bool) -> io::Result<String> {
            Ok(rows(config, mode)?
                .iter()
                .map(|row| {
                    if mode == "full" {
                        row.full_tsv(color)
                    } else {
                        row.lean_tsv()
                    }
                })
                .collect::<Vec<_>>()
                .join("\n"))
        }
        fn cached_lean_rows(config: &Config) -> io::Result<Vec<PaneRow>> {
            if config.now_overridden {
                return rows(config, "lean");
            }
            let cache = config.cache_file();
            let fresh = fs::metadata(&cache).ok().is_some_and(|meta| {
                let age = config.now - meta.mtime();
                !config.now_overridden
                    && config.cache_ttl > 0
                    && (0..=config.cache_ttl).contains(&age)
            });
            let text = if fresh && !is_symlink(&cache) {
                fs::read_to_string(&cache)?
            } else {
                secure_dir(&config.state_dir)?;
                let lock_path = cache.with_extension("cache.lock");
                if lock(&lock_path, config.now, config.cache_lock_stale)? {
                    let written = (|| -> io::Result<String> {
                        let output = rows_text(config, "lean", false)?;
                        atomic_write(&cache, output.as_bytes())?;
                        Ok(output)
                    })();
                    let _ = fs::remove_dir(lock_path);
                    written?
                } else if cache.is_file() && !is_symlink(&cache) {
                    fs::read_to_string(&cache)?
                } else {
                    rows_text(config, "lean", false)?
                }
            };
            Ok(text
                .lines()
                .filter_map(|line| {
                    let values: Vec<_> = line.splitn(4, '\t').collect();
                    let rank: u8 = values.first()?.parse().ok()?;
                    let (session, target) =
                        (values.get(2)?.to_string(), values.get(3)?.to_string());
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
                })
                .collect())
        }
        pub fn session_key(session: &str) -> String {
            session
                .as_bytes()
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect()
        }
        fn render_status(
            config: &Config,
            current: &str,
            sessions: &[String],
            rows: &[PaneRow],
        ) -> String {
            let mut priorities = BTreeMap::<String, SessionPriority>::new();
            for row in rows {
                priorities
                    .entry(row.session.clone())
                    .and_modify(|p| *p = (*p).min(SessionPriority::from_status(row.status)))
                    .or_insert_with(|| SessionPriority::from_status(row.status));
            }
            let global = priorities
                .values()
                .copied()
                .min()
                .unwrap_or(SessionPriority::Other);
            let glyph = match global {
                SessionPriority::Awaiting => &config.config.color_awaiting,
                SessionPriority::Done => &config.config.color_done,
                SessionPriority::Other => &config.config.color_accent,
            };
            let mut current_rows: Vec<_> =
                rows.iter().filter(|row| row.session == current).collect();
            current_rows.sort_by_key(|row| {
                (
                    row.window_index.parse::<u64>().unwrap_or(u64::MAX),
                    row.pane_index.parse::<u64>().unwrap_or(u64::MAX),
                )
            });
            let pill: String = current_rows
                .into_iter()
                .map(|row| {
                    pill_cell(
                        row.status,
                        row.target().split_once(':').map(|x| x.1).unwrap_or(""),
                        &config.config,
                    )
                })
                .collect();
            let pill = if pill.is_empty() {
                format!(
                    "#[fg={},bg={},bold]   #[bg={},nobold]",
                    config.config.color_dim,
                    config.config.color_pill_bg,
                    config.config.color_status_bg
                )
            } else {
                format!(
                    "#[fg={glyph},bg={},bold]   {pill}#[bg={},nobold]",
                    config.config.color_pill_bg, config.config.color_status_bg
                )
            };
            let radar = if sessions.len() > 1 {
                sessions
                    .iter()
                    .enumerate()
                    .map(|(i, session)| {
                        format!(
                            "#[fg={}]{} ",
                            dot_color(
                                *priorities.get(session).unwrap_or(&SessionPriority::Other),
                                session == current,
                                &config.config
                            ),
                            radar_glyph(i + 1, session == current, config.config.radar_numbers)
                        )
                    })
                    .collect::<String>()
            } else {
                String::new()
            };
            format!(
                "{}{}#[default]",
                pill,
                if radar.is_empty() {
                    radar
                } else {
                    format!(" {radar}")
                }
            )
        }
        pub fn status(config: &Config, current: &str) -> io::Result<String> {
            let tmux = Tmux::new(config.tmux.clone());
            let sessions = tmux.sessions()?;
            let rows = cached_lean_rows(config)?;
            let render_config = render_config(config, &tmux);
            Ok(render_status(&render_config, current, &sessions, &rows))
        }
        fn render_config(config: &Config, tmux: &Tmux) -> Config {
            let mut configured = config.clone();
            configured.config.radar_numbers = tmux
                .output(&["show-option", "-gqv", "@agent-radar-radar-numbers"])
                .map(|value| value.trim() == "on")
                .unwrap_or(false);
            configured
        }
        fn lock(path: &Path, now: i64, stale: i64) -> io::Result<bool> {
            if path.is_dir() && now - fs::metadata(path)?.mtime() > stale {
                let _ = fs::remove_dir(path);
            }
            match fs::create_dir(path) {
                Ok(()) => Ok(true),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => Ok(false),
                Err(error) => Err(error),
            }
        }
        pub fn refresh(config: &Config, notify: bool) -> io::Result<()> {
            let directory = config.status_dir();
            secure_dir(&directory)?;
            atomic_write(&directory.join(".pending"), b"")?;
            if notify {
                atomic_write(&directory.join(".notify-pending"), b"")?;
            }
            let lock_path = directory.join(".refresh.lock");
            if !lock(&lock_path, config.now, config.status_lock_stale)? {
                return Ok(());
            }
            let outcome: io::Result<()> = (|| {
                let _ = fs::remove_file(config.cache_file());
                while directory.join(".pending").exists() {
                    fs::remove_file(directory.join(".pending"))?;
                    let tmux = Tmux::new(config.tmux.clone());
                    let sessions = tmux.sessions()?;
                    let fresh_rows = rows(config, "lean")?;
                    let render_config = render_config(config, &tmux);
                    for session in &sessions {
                        atomic_write(
                            &directory.join(format!("{}.txt", session_key(session))),
                            render_status(&render_config, session, &sessions, &fresh_rows)
                                .as_bytes(),
                        )?;
                    }
                    for entry in fs::read_dir(&directory)? {
                        let path = entry?.path();
                        let keep =
                            path.file_name()
                                .and_then(|name| name.to_str())
                                .is_some_and(|name| {
                                    sessions.iter().any(|session| {
                                        name == format!("{}.txt", session_key(session))
                                    })
                                });
                        if path.extension().is_some_and(|x| x == "txt") && !keep {
                            fs::remove_file(path)?;
                        }
                    }
                }
                Ok(())
            })();
            let _ = fs::remove_dir(&lock_path);
            outcome?;
            if notify {
                let _ = Tmux::new(config.tmux.clone()).run(&["refresh-client", "-S"]);
                if let Ok(executable) = env::current_exe() {
                    refresh_popups(config, &executable);
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
            Ok(())
        }
        pub fn cached_status(config: &Config, session: &str) -> io::Result<String> {
            let path = config
                .status_dir()
                .join(format!("{}.txt", session_key(session)));
            if path.is_file() && !is_symlink(&path) {
                return fs::read_to_string(path);
            }
            status(config, session)
        }
        pub fn notification_text(config: &Config) -> io::Result<String> {
            let sessions = Tmux::new(config.tmux.clone())
                .sessions()
                .unwrap_or_default();
            Ok(
                notification_records(&sessions, &rows(config, "notify")?, &config.config)
                    .into_iter()
                    .map(|record| match record {
                        NotificationRecord::Color(value) => format!("COLOR\t{value}"),
                        NotificationRecord::Line { session, kind } => {
                            format!("LINE\t{session}\t{}", kind.as_str())
                        }
                    })
                    .collect::<Vec<_>>()
                    .join("\n"),
            )
        }
        pub fn register_popup(config: &Config, socket: &Path) -> io::Result<PathBuf> {
            let registry = config.state_dir.join(".popups");
            secure_dir(&registry)?;
            let registration = registry.join(std::process::id().to_string());
            atomic_write(
                &registration,
                format!("{}\n{}\n", socket.display(), std::process::id()).as_bytes(),
            )?;
            Ok(registration)
        }
        pub fn refresh_popups(config: &Config, executable: &Path) {
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
                let alive = owner.is_some_and(|pid| unsafe { kill_zero(pid) });
                if !alive || socket.as_ref().map_or(true, |path| !path.exists()) {
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
                    .arg(socket.unwrap())
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
        #[cfg(unix)]
        unsafe fn kill_zero(pid: u32) -> bool {
            extern "C" {
                fn kill(pid: i32, sig: i32) -> i32;
            }
            kill(pid as i32, 0) == 0
        }

        pub fn hook(
            config: &Config,
            event_name: Option<&str>,
            stdin: &mut dyn Read,
        ) -> io::Result<()> {
            let mut input = String::new();
            stdin.read_to_string(&mut input)?;
            let value: Value = serde_json::from_str(if input.trim().is_empty() {
                "{}"
            } else {
                &input
            })
            .map_err(|_| {
                io::Error::new(
                    io::ErrorKind::InvalidData,
                    "hook input must be a JSON object",
                )
            })?;
            let event_name = event_name
                .map(str::to_owned)
                .or_else(|| field(&value, &["hookEventName", "hookName", "eventName", "event"]))
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "missing hook event"))?;
            let event = HookEvent::parse(&event_name)
                .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "unknown hook event"))?;
            let pane = env::var("TMUX_PANE")
                .ok()
                .filter(|p| valid_pane_id(p))
                .or_else(|| resolve_hook_pane(config).ok().flatten())
                .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no valid tmux pane"))?;
            let path = config.state_dir.join(pane_filename(&pane).unwrap());
            let previous =
                read_state(&path, Some(&pane), config.now)?.unwrap_or_else(|| PaneState {
                    pane_id: pane.clone(),
                    session_id: "unknown".into(),
                    process_pid: 1,
                    status: Status::Unknown,
                    event: String::new(),
                    updated_at: String::new(),
                    updated_epoch: 0,
                    tool_name: None,
                    subagent_name: None,
                    flash: None,
                });
            let tool = field(&value, &["toolName", "tool_name"]).or_else(|| {
                let calls = value.get("toolCalls").and_then(Value::as_array)?;
                let names: Vec<String> = calls
                    .iter()
                    .filter_map(|call| field(call, &["name", "toolName", "tool_name"]))
                    .collect();
                Some(
                    names
                        .iter()
                        .find(|name| name.as_str() == "ask_user")
                        .cloned()
                        .or_else(|| names.into_iter().next())
                        .unwrap_or_default(),
                )
            });
            let details = HookDetails {
                tool_name: tool,
                subagent_name: field(&value, &["agentDisplayName", "agentName", "agent_name"]),
                notification_type: field(&value, &["notification_type"]),
                recoverable: value.get("recoverable").and_then(Value::as_bool),
            }
            .sanitized();
            let Some(transition) = fold_hook_event(previous.status, event, &details) else {
                return Ok(());
            };
            if transition.status == Status::Removed {
                let _ = fs::remove_file(path);
                let _ = fs::remove_file(config.state_dir.join(".ack").join(&pane[1..]));
                return Ok(());
            }
            if event == HookEvent::SessionStart
                && previous.process_pid == parent_pid()
                && matches!(previous.status, Status::Working | Status::Awaiting)
            {
                return Ok(());
            }
            let flash = (transition.flash == FlashAction::CreateDone).then(|| Flash {
                kind: FlashKind::Done,
                until_epoch: config.now + config.done_ttl,
                id: Some(format!(
                    "{}-{}-{}",
                    std::process::id(),
                    SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_nanos(),
                    UNIQUE_SEQUENCE.fetch_add(1, AtomicOrdering::Relaxed),
                )),
            });
            let session_id = sanitize_session_id(
                &field(&value, &["sessionId", "session_id"]).unwrap_or_else(unknown_session_id),
            );
            let state = PaneState {
                pane_id: pane.clone(),
                session_id: if session_id.is_empty() {
                    unknown_session_id()
                } else {
                    session_id
                },
                process_pid: parent_pid(),
                status: transition.status,
                event: event_name,
                updated_at: iso_now(),
                updated_epoch: config.now,
                tool_name: details.tool_name,
                subagent_name: details.subagent_name,
                flash,
            };
            write_state(config, &state)?;
            if state.flash.is_none() {
                let _ = fs::remove_file(config.state_dir.join(".ack").join(&pane[1..]));
            }
            if env::var("TMUX_AGENT_STATUS_REFRESH").ok().as_deref() != Some("0") {
                let _ = refresh(config, true);
            }
            Ok(())
        }
        fn field(value: &Value, names: &[&str]) -> Option<String> {
            names
                .iter()
                .find_map(|name| value.get(*name).and_then(Value::as_str).map(str::to_owned))
        }
        fn resolve_hook_pane(config: &Config) -> io::Result<Option<String>> {
            let start = env_i64("TMUX_AGENT_STATUS_PROCESS_PID")
                .unwrap_or(std::process::id() as i64) as u32;
            let processes = match env_path("TMUX_AGENT_STATUS_PS_FILE") {
                Some(path) => parse_process_snapshot(&fs::read_to_string(path)?),
                None => snapshot(config)?,
            };
            let by_pid: BTreeMap<u32, &Process> = processes
                .iter()
                .map(|process| (process.pid, process))
                .collect();
            let mut current = start;
            let mut copilot = None;
            for _ in 0..MAX_ANCESTRY {
                let Some(process) = by_pid.get(&current) else {
                    break;
                };
                if Path::new(&process.command)
                    .file_name()
                    .is_some_and(|name| name == "copilot")
                {
                    copilot = Some(current);
                    break;
                }
                if process.parent == 0 || process.parent == current {
                    break;
                }
                current = process.parent;
            }
            let Some(mut current) = copilot else {
                return Ok(None);
            };
            let parents: BTreeMap<u32, u32> = processes
                .iter()
                .map(|process| (process.pid, process.parent))
                .collect();
            let tmux =
                env::var("TMUX_AGENT_STATUS_TMUX_BIN").unwrap_or_else(|_| config.tmux.clone());
            let roots = Tmux::new(tmux).pane_roots()?;
            for _ in 0..MAX_ANCESTRY {
                if let Some(pane) = roots.get(&current) {
                    return Ok(Some(pane.clone()));
                }
                let Some(next) = parents.get(&current) else {
                    break;
                };
                if *next == 0 || *next == current {
                    break;
                }
                current = *next;
            }
            Ok(None)
        }
        fn parent_pid() -> u32 {
            unsafe { libc_getppid() }
        }
        #[cfg(unix)]
        unsafe fn libc_getppid() -> u32 {
            extern "C" {
                fn getppid() -> i32;
            }
            getppid().max(0) as u32
        }
        fn iso_now() -> String {
            Command::new("date")
                .args(["-u", "+%Y-%m-%dT%H:%M:%SZ"])
                .output()
                .ok()
                .filter(|output| output.status.success())
                .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
                .unwrap_or_else(|| epoch_now().to_string())
        }

        pub fn descriptor(config: &Config, hook: &Path) -> Value {
            let command = format!(
                "env AGENT_RADAR_STATE_DIR={} {}",
                shell_quote(&config.state_dir.to_string_lossy()),
                shell_quote(&hook.to_string_lossy())
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
                    byte.is_ascii_alphanumeric()
                        || matches!(byte, b'/' | b'.' | b'_' | b'-' | b':' | b'=')
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
            hook: &Path,
            legacy: &Path,
        ) -> io::Result<()> {
            secure_dir(&config.state_dir)?;
            migrate(config, legacy)?;
            let parent = descriptor_path.parent().ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidInput, "descriptor has no parent")
            })?;
            secure_dir(parent)?;
            atomic_write(
                descriptor_path,
                &serde_json::to_vec_pretty(&descriptor(config, hook)).unwrap(),
            )?;
            clean_legacy(legacy, &config.state_dir)
        }
        fn migrate(config: &Config, legacy: &Path) -> io::Result<()> {
            if legacy == config.state_dir || !legacy.is_dir() || is_symlink(legacy) {
                return Ok(());
            }
            for entry in fs::read_dir(legacy)? {
                let source = entry?.path();
                if source.extension().is_some_and(|x| x == "json") && !is_symlink(&source) {
                    let parse_legacy = |path: &Path| -> io::Result<Option<PaneState>> {
                        let bytes = match fs::read(path) {
                            Ok(bytes) => bytes,
                            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                                return Ok(None)
                            }
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
                    };
                    if let Some(state) = parse_legacy(&source)? {
                        let dest = config.state_dir.join(source.file_name().unwrap());
                        if parse_legacy(&dest)?
                            .map_or(true, |old| old.updated_epoch < state.updated_epoch)
                        {
                            atomic_write(
                                &dest,
                                &serde_json::to_vec(&state).expect("state serialization"),
                            )?;
                        }
                    }
                }
            }
            Ok(())
        }
        fn clean_legacy(legacy: &Path, destination: &Path) -> io::Result<()> {
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
                if path.extension().is_some_and(|x| x == "json")
                    || path.file_name().is_some_and(|x| x == ".tmux-status.cache")
                    || path
                        .file_name()
                        .and_then(|x| x.to_str())
                        .is_some_and(|x| x.starts_with(".tmux-status.cache."))
                {
                    let _ = fs::remove_file(path);
                } else if path
                    .file_name()
                    .is_some_and(|x| x == ".tmux-status.cache.lock")
                    && path.is_dir()
                {
                    let _ = fs::remove_dir(path);
                } else if path.file_name().is_some_and(|x| x == ".status") && path.is_dir() {
                    for child in fs::read_dir(&path)? {
                        let child = child?.path();
                        if is_symlink(&child) {
                            continue;
                        }
                        let name = child
                            .file_name()
                            .and_then(|x| x.to_str())
                            .unwrap_or_default();
                        if child.extension().is_some_and(|x| x == "txt")
                            || matches!(name, ".stamp" | ".pending" | ".notify-pending")
                        {
                            let _ = fs::remove_file(child);
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
        pub fn doctor(config: &Config, descriptor_path: &Path, hook: &Path) -> (String, bool) {
            let mut lines = Vec::new();
            let mut ok = true;
            for command in ["tmux", "jq", "fzf"] {
                let present = executable_in_path(command);
                lines.push(format!(
                    "{} - {}{}",
                    if present { "ok" } else { "not ok" },
                    if present { "" } else { "missing " },
                    command
                ));
                ok &= present;
            }
            let valid_descriptor = fs::read(descriptor_path)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
                .map(|value| value == descriptor(config, hook))
                .unwrap_or(false);
            lines.push(format!(
                "{} - Copilot hook descriptor",
                if valid_descriptor { "ok" } else { "not ok" }
            ));
            ok &= valid_descriptor;
            let mode_ok = !config.state_dir.exists()
                || (config.state_dir.is_dir()
                    && !is_symlink(&config.state_dir)
                    && fs::metadata(&config.state_dir)
                        .map(|m| m.permissions().mode() & 0o777 == 0o700)
                        .unwrap_or(false));
            lines.push(format!(
                "{} - state directory permissions",
                if mode_ok { "ok" } else { "not ok" }
            ));
            (lines.join("\n"), ok && mode_ok)
        }
        fn executable_in_path(command: &str) -> bool {
            env::var_os("PATH")
                .map(|paths| {
                    env::split_paths(&paths).any(|directory| {
                        fs::metadata(directory.join(command))
                            .map(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
                            .unwrap_or(false)
                    })
                })
                .unwrap_or(false)
        }

        #[cfg(test)]
        mod tests {
            use super::*;
            #[test]
            fn parses_snapshots_and_bounds_ancestry() {
                let panes = parse_panes("%1\ta\t1\t2\t10\ttitle\n%2\tb\t1\t2\t20\ttitle");
                let processes =
                    parse_process_snapshot("10 1 tmux\n11 10 /usr/bin/copilot\n20 1 bash");
                assert_eq!(copilot_pane_pids(&panes, &processes), BTreeSet::from([10]));
            }
            #[test]
            fn accepts_only_safe_panes_and_parses_tabs() {
                assert!(valid_pane_id("%123"));
                assert!(!valid_pane_id("%a"));
                assert_eq!(parse_panes("%1\ts\t0\t1\t2\tx\ty").len(), 1);
                assert_eq!(session_key("A x"), "412078");
            }
            #[test]
            fn makes_descriptor_with_exact_events() {
                let c = Config::from_env();
                let d = descriptor(&c, Path::new("/hook"));
                assert_eq!(d["hooks"].as_object().unwrap().len(), 12);
                assert_eq!(
                    d["hooks"]["notification"][0]["matcher"],
                    "permission_prompt|elicitation_dialog"
                );
            }
        }
    }

    pub use implementation::*;

    #[test]
    fn clears_flash_for_every_other_accepted_event() {
        let notification = HookDetails {
            notification_type: Some("elicitation_dialog".into()),
            ..Default::default()
        };
        for (event, details) in [
            (HookEvent::SessionStart, HookDetails::default()),
            (HookEvent::UserPromptSubmitted, HookDetails::default()),
            (HookEvent::PermissionRequest, HookDetails::default()),
            (HookEvent::PreToolUse, HookDetails::default()),
            (HookEvent::PostToolUse, HookDetails::default()),
            (HookEvent::PostToolUseFailure, HookDetails::default()),
            (HookEvent::Notification, notification),
            (HookEvent::ErrorOccurred, HookDetails::default()),
            (HookEvent::Abort, HookDetails::default()),
            (HookEvent::AgentStop, HookDetails::default()),
            (HookEvent::SubagentStart, HookDetails::default()),
            (HookEvent::SubagentStop, HookDetails::default()),
            (HookEvent::SessionEnd, HookDetails::default()),
        ] {
            assert_eq!(
                fold_hook_event(Status::Idle, event, &details)
                    .unwrap()
                    .flash,
                FlashAction::Clear,
                "{event:?} must clear a prior flash"
            );
        }
        assert_eq!(
            fold_hook_event(
                Status::Working,
                HookEvent::AgentStop,
                &HookDetails::default()
            )
            .unwrap()
            .flash,
            FlashAction::CreateDone
        );
    }

    #[test]
    fn sanitizes_fields_and_copilot_titles() {
        assert_eq!(clean_field("a\tb\r\nc"), "a b  c");
        assert_eq!(clean_title("Task\tName - GitHub Copilot"), "Task Name");
        assert_eq!(clean_title("GitHub Copilot"), "-");
        assert_eq!(clean_title(" - GitHub Copilot"), "-");
        assert_eq!(sanitize_session_id("session / one!"), "sessionone");
        assert_eq!(limit_metadata(&"x".repeat(121)), "x".repeat(120));
        assert_eq!(
            limit_metadata(&format!("{}é", "x".repeat(119))),
            "x".repeat(119)
        );
    }

    #[test]
    fn formats_shell_compatible_rows_without_color() {
        let row = PaneRow {
            pane_id: "%1".into(),
            session: "alpha".into(),
            window_index: "1".into(),
            pane_index: "1".into(),
            title: "Awaiting Hook - GitHub Copilot".into(),
            status: Status::Awaiting,
        };
        assert_eq!(row.lean_tsv(), "1\t%1\talpha\talpha:1.1");
        assert_eq!(row.full_tsv(false),
            "1\t%1\talpha\talpha:1.1\t⏸ awaiting\tAwaiting Hook\tawaiting    alpha:1.1                   Awaiting Hook");
    }

    #[test]
    fn uses_byte_precisions_without_invalid_utf8() {
        assert_eq!(
            truncate_utf8_bytes("abcdefghijklmnopqrstuvwxyz", 26),
            "abcdefghijklmnopqrstuvwxyz"
        );
        assert_eq!(
            truncate_utf8_bytes("abcdefghijklmnopqrstuvwxyz!", 26),
            "abcdefghijklmnopqrstuvwxyz"
        );
        assert_eq!(
            truncate_utf8_bytes(&format!("{}é", "x".repeat(119)), 120),
            "x".repeat(119)
        );
        assert_eq!(truncate_utf8_bytes("éclair", 1), "");

        let row = format_display_row(Status::Idle, "1234567890123456789012345é", "-", false);
        assert_eq!(row, "idle        1234567890123456789012345   -");
        assert!(std::str::from_utf8(row.as_bytes()).is_ok());
    }

    #[test]
    fn renders_labels_pills_colors_and_radar_glyphs() {
        let config = RadarConfig::default();
        assert_eq!(status_label(Status::Working, false), "⚙ working");
        assert_eq!(
            pill_cell(Status::Done, "1.4", &config),
            "#[fg=#3fb950,bold]✓1.4 "
        );
        assert_eq!(dot_color(SessionPriority::Other, true, &config), "#9ece6a");
        assert_eq!(radar_glyph(2, false, false), "●");
        assert_eq!(radar_glyph(1, false, true), "\u{f0ca0}");
        assert_eq!(radar_glyph(10, false, true), "\u{f0fec}");
        assert_eq!(radar_glyph(11, true, true), "◉");
    }

    #[test]
    fn folds_done_for_popup_and_notification_and_notifies_in_session_order() {
        let state = PaneState {
            pane_id: "%1".into(),
            session_id: "alpha".into(),
            process_pid: 1,
            status: Status::Idle,
            event: "agentStop".into(),
            updated_at: "now".into(),
            updated_epoch: 1,
            tool_name: None,
            subagent_name: None,
            flash: Some(Flash {
                kind: FlashKind::Done,
                until_epoch: 5,
                id: Some("done-1".into()),
            }),
        };
        assert_eq!(effective_status(&state, 10, None, false), Status::Done);
        assert_eq!(effective_status(&state, 10, None, true), Status::Idle);
        assert_eq!(
            effective_status(&state, 1, Some("done-1"), true),
            Status::Idle
        );

        let config = RadarConfig::default();
        let rows = vec![
            PaneRow {
                pane_id: "%1".into(),
                session: "solo".into(),
                window_index: "1".into(),
                pane_index: "1".into(),
                title: "-".into(),
                status: Status::Awaiting,
            },
            PaneRow {
                pane_id: "%2".into(),
                session: "duo".into(),
                window_index: "1".into(),
                pane_index: "1".into(),
                title: "-".into(),
                status: Status::Done,
            },
        ];
        assert_eq!(
            notification_records(&["solo".into(), "duo".into()], &rows, &config),
            vec![
                NotificationRecord::Color("#f7768e".into()),
                NotificationRecord::Line {
                    session: "solo".into(),
                    kind: Status::Awaiting
                },
                NotificationRecord::Line {
                    session: "duo".into(),
                    kind: Status::Done
                },
            ]
        );
    }

    #[test]
    fn notifies_unordered_sessions_in_stable_lexical_order() {
        let config = RadarConfig::default();
        let rows = vec![
            PaneRow {
                pane_id: "%1".into(),
                session: "zulu".into(),
                window_index: "1".into(),
                pane_index: "1".into(),
                title: "-".into(),
                status: Status::Done,
            },
            PaneRow {
                pane_id: "%2".into(),
                session: "bravo".into(),
                window_index: "1".into(),
                pane_index: "1".into(),
                title: "-".into(),
                status: Status::Awaiting,
            },
            PaneRow {
                pane_id: "%3".into(),
                session: "alpha".into(),
                window_index: "1".into(),
                pane_index: "1".into(),
                title: "-".into(),
                status: Status::Done,
            },
        ];
        assert_eq!(
            notification_records(&["zulu".into()], &rows, &config),
            vec![
                NotificationRecord::Color("#f7768e".into()),
                NotificationRecord::Line {
                    session: "zulu".into(),
                    kind: Status::Done
                },
                NotificationRecord::Line {
                    session: "alpha".into(),
                    kind: Status::Done
                },
                NotificationRecord::Line {
                    session: "bravo".into(),
                    kind: Status::Awaiting
                },
            ]
        );
    }
}
