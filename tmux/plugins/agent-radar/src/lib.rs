use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cmp::Ordering;
use std::collections::{BTreeMap, BTreeSet};
use std::env;
use std::fs;
use std::io::{self, Read};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

mod popup;
mod state;
mod tmux;

pub use state::{ack_token, acknowledge, read_state, valid_pane_id, valid_state, write_state};
pub use tmux::{copilot_pane_pids, parse_panes, parse_process_snapshot, Process, Tmux, TmuxPane};

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
    Working,
    Other,
}

impl SessionPriority {
    pub const fn from_status(status: Status) -> Self {
        match status {
            Status::Awaiting => Self::Awaiting,
            Status::Done => Self::Done,
            Status::Working => Self::Working,
            _ => Self::Other,
        }
    }

    const fn as_u8(self) -> u8 {
        match self {
            Self::Awaiting => 0,
            Self::Done => 1,
            Self::Working => 2,
            Self::Other => 3,
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
        HookEvent::SessionStart if matches!(previous, Status::Working | Status::Awaiting) => {
            return None;
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
        HookEvent::ErrorOccurred if details.recoverable == Some(true) => Status::Working,
        HookEvent::ErrorOccurred | HookEvent::Abort | HookEvent::AgentStop => Status::Idle,
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
            self.status.rank().map_or(5, |rank| rank as u8),
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
            self.status.rank().map_or(5, |rank| rank as u8),
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
        }
    }
}

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
    pub theme: RadarConfig,
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
        let now_overridden = env::var_os("TMUX_AGENT_ENGINE_NOW").is_some();
        let mut theme = RadarConfig::default();
        set_color(&mut theme.color_awaiting, "AGENT_RADAR_COLOR_AWAITING");
        set_color(&mut theme.color_working, "AGENT_RADAR_COLOR_WORKING");
        set_color(&mut theme.color_done, "AGENT_RADAR_COLOR_DONE");
        set_color(&mut theme.color_idle, "AGENT_RADAR_COLOR_IDLE");
        set_color(&mut theme.color_accent, "AGENT_RADAR_COLOR_ACCENT");
        set_color(&mut theme.color_muted, "AGENT_RADAR_COLOR_MUTED");
        set_color(&mut theme.color_dim, "AGENT_RADAR_COLOR_DIM");
        set_color(&mut theme.color_pill_bg, "AGENT_RADAR_COLOR_PILL_BG");
        set_color(&mut theme.color_status_bg, "AGENT_RADAR_COLOR_STATUS_BG");
        Self {
            state_dir,
            tmux: env::var("AGENT_RADAR_TMUX_BIN")
                .or_else(|_| env::var("TMUX_AGENT_ENGINE_TMUX_BIN"))
                .unwrap_or_else(|_| "tmux".into()),
            now: env_i64("TMUX_AGENT_ENGINE_NOW").unwrap_or_else(epoch_now),
            now_overridden,
            cache_ttl: env_i64("AGENT_RADAR_CACHE_TTL")
                .or_else(|| env_i64("TMUX_AGENT_ENGINE_CACHE_TTL"))
                .unwrap_or(2),
            done_ttl: env_i64("AGENT_RADAR_DONE_TTL")
                .or_else(|| env_i64("TMUX_AGENT_STATUS_DONE_TTL"))
                .unwrap_or(3),
            status_lock_stale: env_i64("TMUX_AGENT_ENGINE_STATUS_LOCK_STALE").unwrap_or(30),
            cache_lock_stale: env_i64("TMUX_AGENT_ENGINE_CACHE_LOCK_STALE").unwrap_or(30),
            process_snapshot: env_path("TMUX_AGENT_ENGINE_PS_FILE"),
            theme,
        }
    }

    pub fn cache_file(&self) -> PathBuf {
        env_path("TMUX_AGENT_ENGINE_CACHE_FILE")
            .unwrap_or_else(|| self.state_dir.join(".tmux-status.cache"))
    }

    pub fn status_dir(&self) -> PathBuf {
        env_path("TMUX_AGENT_ENGINE_STATUS_DIR").unwrap_or_else(|| self.state_dir.join(".status"))
    }
}

pub(crate) fn env_path(name: &str) -> Option<PathBuf> {
    env::var_os(name)
        .filter(|value| !value.is_empty())
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

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RowMode {
    Full,
    Lean,
    Notify,
}

impl From<&str> for RowMode {
    fn from(value: &str) -> Self {
        match value {
            "full" => Self::Full,
            "notify" => Self::Notify,
            _ => Self::Lean,
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
    if !color {
        return status.label().into();
    }
    format!("\x1b[38;2;{}m{}\x1b[0m", rgb(status), status.label())
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

pub fn pill_cell(status: Status, pane_target: &str, theme: &RadarConfig) -> String {
    match status {
        Status::Awaiting => format!("#[fg={},bold]{} ", theme.color_awaiting, pane_target),
        Status::Working => format!("#[fg={},bold]{} ", theme.color_working, pane_target),
        Status::Done => format!("#[fg={},bold]✓{} ", theme.color_done, pane_target),
        Status::Idle => format!("#[fg={},nobold]{} ", theme.color_idle, pane_target),
        Status::Unknown | Status::Removed => {
            format!("#[fg={},nobold]{} ", theme.color_muted, pane_target)
        }
    }
}

pub fn badge_color(priority: SessionPriority, is_current: bool, theme: &RadarConfig) -> &str {
    match priority {
        SessionPriority::Awaiting => &theme.color_awaiting,
        SessionPriority::Done => &theme.color_done,
        SessionPriority::Working => &theme.color_working,
        SessionPriority::Other if is_current => &theme.color_idle,
        SessionPriority::Other => &theme.color_muted,
    }
}

/// Returns a darker shade of a `#RRGGBB` color by scaling each channel toward
/// black. Falls back to the input when it is not a 6-digit hex string.
pub fn darken_hex(hex: &str, factor: f32) -> String {
    let channel = |range: std::ops::Range<usize>| -> Option<u8> {
        hex.get(range)
            .and_then(|part| u8::from_str_radix(part, 16).ok())
    };
    match (channel(1..3), channel(3..5), channel(5..7)) {
        (Some(r), Some(g), Some(b)) if hex.starts_with('#') && hex.len() == 7 => {
            let scale = |value: u8| (f32::from(value) * factor).round().clamp(0.0, 255.0) as u8;
            format!("#{:02x}{:02x}{:02x}", scale(r), scale(g), scale(b))
        }
        _ => hex.to_string(),
    }
}

pub fn radar_label(position: usize) -> String {
    match position {
        1..=9 => position.to_string(),
        10 => "0".to_string(),
        other => other.to_string(),
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

fn session_priorities(rows: &[PaneRow]) -> BTreeMap<&str, SessionPriority> {
    let mut priorities: BTreeMap<&str, SessionPriority> = BTreeMap::new();
    for row in rows {
        priorities
            .entry(row.session.as_str())
            .and_modify(|priority| {
                *priority = (*priority).min(SessionPriority::from_status(row.status));
            })
            .or_insert_with(|| SessionPriority::from_status(row.status));
    }
    priorities
}

pub fn notification_records(
    session_order: &[String],
    rows: &[PaneRow],
    theme: &RadarConfig,
) -> Vec<NotificationRecord> {
    if rows.is_empty() {
        return Vec::new();
    }
    let priorities = session_priorities(rows);
    let global = priorities
        .values()
        .copied()
        .min()
        .unwrap_or(SessionPriority::Other);
    let color = match global {
        SessionPriority::Awaiting => &theme.color_awaiting,
        SessionPriority::Done => &theme.color_done,
        SessionPriority::Working | SessionPriority::Other => &theme.color_accent,
    };
    let mut records = vec![NotificationRecord::Color(color.clone())];
    let mut emitted = BTreeSet::new();
    for session in session_order {
        if let Some(priority @ (SessionPriority::Awaiting | SessionPriority::Done)) =
            priorities.get(session.as_str())
        {
            records.push(NotificationRecord::Line {
                session: session.clone(),
                kind: priority_status(*priority),
            });
            emitted.insert(session.as_str());
        }
    }
    for (session, priority) in priorities {
        if !emitted.contains(session)
            && matches!(priority, SessionPriority::Awaiting | SessionPriority::Done)
        {
            records.push(NotificationRecord::Line {
                session: session.into(),
                kind: priority_status(priority),
            });
        }
    }
    records
}

fn priority_status(priority: SessionPriority) -> Status {
    match priority {
        SessionPriority::Awaiting => Status::Awaiting,
        SessionPriority::Done => Status::Done,
        SessionPriority::Working => Status::Working,
        SessionPriority::Other => Status::Unknown,
    }
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

pub fn rows(config: &Config, mode: impl Into<RowMode>) -> io::Result<Vec<PaneRow>> {
    rows_excluding(config, mode.into(), &BTreeSet::new())
}

fn rows_excluding(
    config: &Config,
    mode: RowMode,
    excluded_panes: &BTreeSet<String>,
) -> io::Result<Vec<PaneRow>> {
    let tmux = Tmux::new(config.tmux.clone());
    let panes = tmux.panes()?;
    let live = copilot_pane_pids(&panes, &tmux::snapshot(config)?);
    let mut result = Vec::new();
    for pane in panes
        .iter()
        .filter(|pane| live.contains(&pane.pid) && !excluded_panes.contains(&pane.pane_id))
    {
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
                    state::acknowledged(config, &pane.pane_id).as_deref(),
                    mode == RowMode::Notify,
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
    state::prune(
        config,
        &panes
            .iter()
            .map(|pane| pane.pane_id[1..].to_owned())
            .collect(),
    )?;
    result.sort_by(|left, right| {
        (
            left.status.rank().map_or(5, |rank| rank as u8),
            &left.session,
            left.target(),
        )
            .cmp(&(
                right.status.rank().map_or(5, |rank| rank as u8),
                &right.session,
                right.target(),
            ))
    });
    Ok(result)
}

pub fn rows_text(config: &Config, mode: impl Into<RowMode>, color: bool) -> io::Result<String> {
    let mode = mode.into();
    Ok(rows(config, mode)?
        .iter()
        .map(|row| match mode {
            RowMode::Full => row.full_tsv(color),
            RowMode::Lean | RowMode::Notify => row.lean_tsv(),
        })
        .collect::<Vec<_>>()
        .join("\n"))
}

fn cached_lean_rows(config: &Config) -> io::Result<Vec<PaneRow>> {
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

fn render_status(config: &Config, current: &str, sessions: &[String], rows: &[PaneRow]) -> String {
    let priorities = session_priorities(rows);
    let global = priorities
        .values()
        .copied()
        .min()
        .unwrap_or(SessionPriority::Other);
    let glyph = match global {
        SessionPriority::Awaiting => &config.theme.color_awaiting,
        SessionPriority::Done => &config.theme.color_done,
        SessionPriority::Working | SessionPriority::Other => &config.theme.color_accent,
    };
    let mut current_rows: Vec<_> = rows.iter().filter(|row| row.session == current).collect();
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
                row.target().split_once(':').map_or("", |value| value.1),
                &config.theme,
            )
        })
        .collect();
    let pill = if pill.is_empty() {
        format!(
            "#[fg={},bg={},bold]   #[bg={},nobold]",
            config.theme.color_dim, config.theme.color_pill_bg, config.theme.color_status_bg
        )
    } else {
        format!(
            "#[fg={glyph},bg={},bold]   {pill}#[bg={},nobold]",
            config.theme.color_pill_bg, config.theme.color_status_bg
        )
    };
    let radar = if sessions.len() > 1 {
        sessions
            .iter()
            .enumerate()
            .map(|(index, session)| {
                let priority = *priorities
                    .get(session.as_str())
                    .unwrap_or(&SessionPriority::Other);
                let is_current = session == current;
                let label = radar_label(index + 1);
                let signal = is_current
                    || matches!(
                        priority,
                        SessionPriority::Awaiting
                            | SessionPriority::Done
                            | SessionPriority::Working
                    );
                if is_current {
                    // Focused session: same footprint as any other badge, but its
                    // border cells use a darker shade of the status color so the
                    // focused session stays distinguishable even when it and other
                    // sessions share the same status color.
                    let color = badge_color(priority, is_current, &config.theme);
                    let border = darken_hex(color, 0.6);
                    format!(
                        "#[fg={bg},bg={border},bold] #[bg={color}]{label}#[bg={border}] #[default] ",
                        bg = config.theme.color_status_bg,
                        border = border,
                        color = color,
                        label = label,
                    )
                } else if signal {
                    format!(
                        "#[fg={},bg={},bold] {} #[default] ",
                        config.theme.color_status_bg,
                        badge_color(priority, is_current, &config.theme),
                        label,
                    )
                } else {
                    format!("#[fg={},nobold]{} ", config.theme.color_muted, label)
                }
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
    Ok(render_status(config, current, &sessions, &rows))
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

pub fn refresh(config: &Config, notify: bool) -> io::Result<()> {
    refresh_excluding(config, notify, None)
}

fn refresh_excluding(config: &Config, notify: bool, excluded_pane: Option<&str>) -> io::Result<()> {
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
        state::atomic_write(
            &directory.join(format!("{}.txt", session_key(session))),
            render_status(config, session, &sessions, &fresh_rows).as_bytes(),
        )?;
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
        popup::refresh(config, &executable);
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

pub fn notification_text(config: &Config) -> io::Result<String> {
    let sessions = Tmux::new(config.tmux.clone())
        .sessions()
        .unwrap_or_default();
    Ok(
        notification_records(&sessions, &rows(config, RowMode::Notify)?, &config.theme)
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

pub fn hook(config: &Config, event_name: Option<&str>, stdin: &mut dyn Read) -> io::Result<()> {
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
        .filter(|pane| valid_pane_id(pane))
        .or_else(|| {
            let start = env_i64("TMUX_AGENT_STATUS_PROCESS_PID")
                .unwrap_or(std::process::id() as i64) as u32;
            tmux::resolve_hook_pane(config, start).ok().flatten()
        })
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no valid tmux pane"))?;
    let path = config
        .state_dir
        .join(state::pane_filename(&pane).expect("validated pane"));
    let previous = read_state(&path, Some(&pane), config.now)?.unwrap_or_else(|| PaneState {
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
    let details = hook_details(&value).sanitized();
    let Some(transition) = fold_hook_event(previous.status, event, &details) else {
        return Ok(());
    };
    if transition.status == Status::Removed {
        state::remove_pane(config, &pane);
        if env::var("TMUX_AGENT_STATUS_REFRESH").ok().as_deref() != Some("0") {
            let _ = refresh_excluding(config, true, Some(&pane));
        }
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
            state::unique_sequence(),
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
        state::remove_file(config.state_dir.join(".ack").join(&pane[1..]));
    }
    if env::var("TMUX_AGENT_STATUS_REFRESH").ok().as_deref() != Some("0") {
        let _ = refresh(config, true);
    }
    Ok(())
}

fn hook_details(value: &Value) -> HookDetails {
    let tool_name = field(value, &["toolName", "tool_name"]).or_else(|| {
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
    HookDetails {
        tool_name,
        subagent_name: field(value, &["agentDisplayName", "agentName", "agent_name"]),
        notification_type: field(value, &["notification_type"]),
        recoverable: value.get("recoverable").and_then(Value::as_bool),
    }
}

fn field(value: &Value, names: &[&str]) -> Option<String> {
    names
        .iter()
        .find_map(|name| value.get(*name).and_then(Value::as_str).map(str::to_owned))
}

fn parent_pid() -> u32 {
    unsafe {
        unsafe extern "C" {
            fn getppid() -> i32;
        }
        getppid().max(0) as u32
    }
}

fn iso_now() -> String {
    format_iso_utc(epoch_now())
}

pub fn format_iso_utc(epoch: i64) -> String {
    let days = epoch.div_euclid(86_400);
    let seconds = epoch.rem_euclid(86_400);
    let (hour, minute, second) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60);
    // Howard Hinnant's civil-from-days algorithm (epoch shifted to 0000-03-01).
    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_position = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_position + 2) / 5 + 1;
    let month = if month_position < 10 {
        month_position + 3
    } else {
        month_position - 9
    };
    let year = if month <= 2 { year + 1 } else { year };
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
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
    hook: &Path,
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
        &serde_json::to_vec_pretty(&descriptor(config, hook)).expect("descriptor serialization"),
    )?;
    state::clean_legacy(legacy, &config.state_dir)
}

pub fn doctor(config: &Config, descriptor_path: &Path, hook: &Path) -> (String, bool) {
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
        .is_some_and(|value| value == descriptor(config, hook));
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

pub fn install_default(config: &Config) -> Result<PathBuf, String> {
    let descriptor = descriptor_path();
    install(
        &configured_setup_config(config),
        &descriptor,
        &hook_path()?,
        &legacy_state_dir(),
    )
    .map_err(|error| error.to_string())?;
    Ok(descriptor)
}

pub fn doctor_default(config: &Config) -> Result<(String, bool), String> {
    Ok(doctor(
        &configured_setup_config(config),
        &descriptor_path(),
        &hook_path()?,
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

fn hook_path() -> Result<PathBuf, String> {
    if let Some(path) = env::var_os("AGENT_RADAR_HOOK_BIN") {
        return Ok(path.into());
    }
    let binary = env::current_exe().map_err(|error| error.to_string())?;
    Ok(binary
        .parent()
        .ok_or_else(|| "agent-radar executable has no parent directory".to_owned())?
        .join("agent-radar-hook"))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn working_badge_lights_up_like_awaiting_and_done() {
        let theme = RadarConfig::default();
        // Working fills the badge yellow whether or not it is the focused session.
        assert_eq!(
            badge_color(SessionPriority::Working, true, &theme),
            theme.color_working.as_str()
        );
        assert_eq!(
            badge_color(SessionPriority::Working, false, &theme),
            theme.color_working.as_str()
        );
        // A plain (idle/other) session is still green when current, muted otherwise.
        assert_eq!(
            badge_color(SessionPriority::Other, true, &theme),
            theme.color_idle.as_str()
        );
        assert_eq!(
            badge_color(SessionPriority::Other, false, &theme),
            theme.color_muted.as_str()
        );
        // Awaiting/done still outrank working for the badge.
        assert!(SessionPriority::Awaiting < SessionPriority::Working);
        assert!(SessionPriority::Done < SessionPriority::Working);
    }

    #[test]
    fn formats_iso_utc_without_a_subprocess() {
        assert_eq!(format_iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_iso_utc(1_000_000_000), "2001-09-09T01:46:40Z");
        assert_eq!(format_iso_utc(1_774_084_867), "2026-03-21T09:21:07Z");
        // Leap-day handling.
        assert_eq!(format_iso_utc(1_582_934_400), "2020-02-29T00:00:00Z");
    }

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
                flash: FlashAction::Clear,
            })
        );
        assert_eq!(
            fold_hook_event(
                Status::Working,
                HookEvent::SessionStart,
                &HookDetails::default()
            ),
            None
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
        assert_eq!(
            row.full_tsv(false),
            "1\t%1\talpha\talpha:1.1\t⏸ awaiting\tAwaiting Hook\tawaiting    alpha:1.1                   Awaiting Hook"
        );
    }

    #[test]
    fn makes_descriptor_with_exact_events() {
        let config = Config::from_env();
        let descriptor = descriptor(&config, Path::new("/hook"));
        assert_eq!(descriptor["hooks"].as_object().expect("hooks").len(), 12);
        assert_eq!(
            descriptor["hooks"]["notification"][0]["matcher"],
            "permission_prompt|elicitation_dialog"
        );
    }
}
