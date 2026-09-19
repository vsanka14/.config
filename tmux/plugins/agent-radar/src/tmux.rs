use crate::state::valid_pane_id;
use crate::Config;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

const MAX_ANCESTRY: usize = 256;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Process {
    pub pid: u32,
    pub parent: u32,
    pub command: String,
}

#[derive(Clone, Debug)]
pub(crate) struct ProcessTree<'a> {
    processes: &'a [Process],
    parents: BTreeMap<u32, u32>,
}

impl<'a> ProcessTree<'a> {
    fn new(processes: &'a [Process]) -> Self {
        Self {
            processes,
            parents: processes
                .iter()
                .map(|process| (process.pid, process.parent))
                .collect(),
        }
    }

    fn ancestors(&self, start: u32) -> impl Iterator<Item = u32> + '_ {
        std::iter::successors(Some(start), |current| {
            let parent = self.parents.get(current).copied()?;
            (parent != 0 && parent != *current).then_some(parent)
        })
        .take(MAX_ANCESTRY)
    }

    fn nearest_named(&self, start: u32, name: &str) -> Option<u32> {
        let commands: BTreeMap<u32, &str> = self
            .processes
            .iter()
            .map(|process| (process.pid, process.command.as_str()))
            .collect();
        self.ancestors(start).find(|pid| {
            commands.get(pid).is_some_and(|command| {
                Path::new(command)
                    .file_name()
                    .is_some_and(|file_name| file_name == name)
            })
        })
    }

    fn first_root<T: Clone>(&self, start: u32, roots: &BTreeMap<u32, T>) -> Option<T> {
        self.ancestors(start)
            .find_map(|pid| roots.get(&pid).cloned())
    }
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

pub fn copilot_pane_pids(panes: &[TmuxPane], processes: &[Process]) -> BTreeSet<u32> {
    let tree = ProcessTree::new(processes);
    let roots: BTreeMap<u32, u32> = panes.iter().map(|pane| (pane.pid, pane.pid)).collect();
    processes
        .iter()
        .filter(|process| {
            Path::new(&process.command)
                .file_name()
                .is_some_and(|name| name == "copilot")
        })
        .filter_map(|process| tree.first_root(process.pid, &roots))
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
            Err(io::Error::other(
                String::from_utf8_lossy(&output.stderr).into_owned(),
            ))
        }
    }

    pub fn run(&self, args: &[&str]) -> io::Result<()> {
        self.output(args).map(|_| ())
    }

    pub fn panes(&self) -> io::Result<Vec<TmuxPane>> {
        Ok(parse_panes(&self.output(&[
            "list-panes",
            "-a",
            "-F",
            "#{pane_id}\t#{session_name}\t#{window_index}\t#{pane_index}\t#{pane_pid}\t#{pane_title}",
        ])?))
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

pub(crate) fn snapshot(config: &Config) -> io::Result<Vec<Process>> {
    let text = match &config.process_snapshot {
        Some(path) => fs::read_to_string(path)?,
        None => {
            let output = Command::new("ps")
                .args(["-axo", "pid=,ppid=,comm="])
                .output()?;
            if !output.status.success() {
                return Err(io::Error::other(
                    String::from_utf8_lossy(&output.stderr).into_owned(),
                ));
            }
            String::from_utf8_lossy(&output.stdout).into_owned()
        }
    };
    Ok(parse_process_snapshot(&text))
}

pub(crate) fn resolve_hook_pane(config: &Config, start: u32) -> io::Result<Option<String>> {
    let processes = match crate::env_path("TMUX_AGENT_STATUS_PS_FILE") {
        Some(path) => parse_process_snapshot(&fs::read_to_string(path)?),
        None => snapshot(config)?,
    };
    let tree = ProcessTree::new(&processes);
    let Some(copilot) = tree.nearest_named(start, "copilot") else {
        return Ok(None);
    };
    let tmux = std::env::var("TMUX_AGENT_STATUS_TMUX_BIN").unwrap_or_else(|_| config.tmux.clone());
    Ok(tree.first_root(copilot, &Tmux::new(tmux).pane_roots()?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_snapshots_and_bounds_ancestry() {
        let panes = parse_panes("%1\ta\t1\t2\t10\ttitle\n%2\tb\t1\t2\t20\ttitle");
        let processes = parse_process_snapshot("10 1 tmux\n11 10 /usr/bin/copilot\n20 1 copilot");
        assert_eq!(
            copilot_pane_pids(&panes, &processes),
            BTreeSet::from([10, 20])
        );
    }

    #[test]
    fn ancestry_includes_the_starting_pid() {
        let processes = parse_process_snapshot("20 1 /usr/bin/copilot");
        let tree = ProcessTree::new(&processes);
        assert_eq!(tree.nearest_named(20, "copilot"), Some(20));
        assert_eq!(
            tree.first_root(20, &BTreeMap::from([(20, "%2")])),
            Some("%2")
        );
    }

    #[test]
    fn parses_tabs() {
        assert_eq!(parse_panes("%1\ts\t0\t1\t2\tx\ty").len(), 1);
    }
}
