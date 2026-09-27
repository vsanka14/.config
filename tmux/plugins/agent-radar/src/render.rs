use crate::{PaneRow, RadarConfig, SessionPriority, Status};
use std::collections::BTreeMap;

pub const COPILOT_TITLE_SUFFIX: &str = " - GitHub Copilot";

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

pub fn clean_field(value: &str) -> String {
    value.replace(['\t', '\r', '\n'], " ")
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

pub fn radar_label(position: usize) -> String {
    match position {
        1..=9 => position.to_string(),
        10 => "0".to_string(),
        other => other.to_string(),
    }
}

pub(crate) fn session_priorities(rows: &[PaneRow]) -> BTreeMap<&str, SessionPriority> {
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

pub(crate) fn render_status(
    theme: &RadarConfig,
    current: &str,
    sessions: &[String],
    rows: &[PaneRow],
) -> String {
    let priorities = session_priorities(rows);
    let global = priorities
        .values()
        .copied()
        .min()
        .unwrap_or(SessionPriority::Other);
    let glyph = match global {
        SessionPriority::Awaiting => &theme.color_awaiting,
        SessionPriority::Done => &theme.color_done,
        SessionPriority::Working | SessionPriority::Other => &theme.color_accent,
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
                theme,
            )
        })
        .collect();
    let pill = if pill.is_empty() {
        format!(
            "#[fg={},bg={},bold]   #[bg={},nobold]",
            theme.color_dim, theme.color_pill_bg, theme.color_status_bg
        )
    } else {
        format!(
            "#[fg={glyph},bg={},bold]   {pill}#[bg={},nobold]",
            theme.color_pill_bg, theme.color_status_bg
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
                    format!(
                        "#[fg={},bg={},bold] {} #[default] ",
                        theme.color_status_bg,
                        badge_color(priority, is_current, theme),
                        label,
                    )
                } else if signal {
                    format!(
                        "#[fg={},bold]{} ",
                        badge_color(priority, is_current, theme),
                        label,
                    )
                } else {
                    format!("#[fg={},nobold]{} ", theme.color_muted, label)
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

fn rgb(status: Status) -> &'static str {
    match status {
        Status::Awaiting => "247;118;142",
        Status::Working => "224;175;104",
        Status::Done => "63;185;80",
        Status::Idle => "158;206;106",
        Status::Unknown | Status::Removed => "86;95;137",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn working_badge_lights_up_like_awaiting_and_done() {
        let theme = RadarConfig::default();
        assert_eq!(
            badge_color(SessionPriority::Working, true, &theme),
            theme.color_working.as_str()
        );
        assert_eq!(
            badge_color(SessionPriority::Working, false, &theme),
            theme.color_working.as_str()
        );
        assert_eq!(
            badge_color(SessionPriority::Other, true, &theme),
            theme.color_idle.as_str()
        );
        assert_eq!(
            badge_color(SessionPriority::Other, false, &theme),
            theme.color_muted.as_str()
        );
        assert!(SessionPriority::Awaiting < SessionPriority::Working);
        assert!(SessionPriority::Done < SessionPriority::Working);
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
}
