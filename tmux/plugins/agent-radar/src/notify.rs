use crate::render::session_priorities;
use crate::{rows, Config, PaneRow, RadarConfig, RowMode, SessionPriority, Status, Tmux};
use std::collections::BTreeSet;
use std::io;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum NotificationRecord {
    Color(String),
    Line { session: String, kind: Status },
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
