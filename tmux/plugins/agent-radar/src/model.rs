use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

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

pub(crate) fn unknown_session_id() -> String {
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
