use crate::config::{env_i64, epoch_now};
use crate::model::unknown_session_id;
use crate::state;
use crate::{
    read_state, refresh, valid_pane_id, write_state, Config, Flash, FlashKind, PaneState, Status,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::env;
use std::io::{self, Read};
use std::time::{SystemTime, UNIX_EPOCH};

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

pub fn sanitize_session_id(value: &str) -> String {
    value
        .chars()
        .filter(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
        .collect()
}

pub fn limit_metadata(value: &str) -> String {
    crate::truncate_utf8_bytes(value, 120).into()
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
            crate::tmux::resolve_hook_pane(config, start).ok().flatten()
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
            let _ = crate::refresh::refresh_excluding(config, true, Some(&pane));
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_iso_utc_without_a_subprocess() {
        assert_eq!(format_iso_utc(0), "1970-01-01T00:00:00Z");
        assert_eq!(format_iso_utc(1_000_000_000), "2001-09-09T01:46:40Z");
        assert_eq!(format_iso_utc(1_774_084_867), "2026-03-21T09:21:07Z");
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
}
