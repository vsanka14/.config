use crate::state;
use crate::{clean_field, copilot_pane_pids, Config, FlashKind, PaneRow, PaneState, Status, Tmux};
use std::collections::BTreeSet;
use std::io;

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

pub fn rows(config: &Config, mode: impl Into<RowMode>) -> io::Result<Vec<PaneRow>> {
    rows_excluding(config, mode.into(), &BTreeSet::new())
}

pub(crate) fn rows_excluding(
    config: &Config,
    mode: RowMode,
    excluded_panes: &BTreeSet<String>,
) -> io::Result<Vec<PaneRow>> {
    let tmux = Tmux::new(config.tmux.clone());
    let panes = tmux.panes()?;
    let live = copilot_pane_pids(&panes, &crate::tmux::snapshot(config)?);
    let mut result = Vec::new();
    for pane in panes
        .iter()
        .filter(|pane| live.contains(&pane.pid) && !excluded_panes.contains(&pane.pane_id))
    {
        let state = crate::read_state(
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
