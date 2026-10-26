#![allow(dead_code)]

//! Shared black-box fixtures for the integration suites.

use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);

pub const NOW: i64 = 2_000_000_000;

pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub fn new(label: &str) -> Self {
        let path = std::env::temp_dir().join(format!(
            "agent-radar-test-{label}-{}-{}",
            std::process::id(),
            NEXT_TEMP.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir_all(&path).expect("create test directory");
        Self { path }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

#[derive(Clone)]
struct Session {
    name: String,
    created: i64,
}

#[derive(Clone)]
struct Pane {
    id: String,
    session: String,
    window: u32,
    index: u32,
    pid: u32,
    title: String,
}

pub struct Scenario {
    temp: TempDir,
    sessions: Vec<Session>,
    panes: Vec<Pane>,
    processes: Vec<(u32, u32, String)>,
    now: i64,
    extra_env: BTreeMap<String, String>,
}

impl Scenario {
    pub fn new(label: &str) -> Self {
        let temp = TempDir::new(label);
        for directory in ["state", "options"] {
            fs::create_dir_all(temp.path().join(directory)).expect("create fixture directory");
        }
        write_executable(&temp.path().join("fake-tmux"), FAKE_TMUX);
        Self {
            temp,
            sessions: Vec::new(),
            panes: Vec::new(),
            processes: Vec::new(),
            now: NOW,
            extra_env: BTreeMap::new(),
        }
    }

    pub fn session(mut self, name: &str, created: i64) -> Self {
        self.sessions.push(Session {
            name: name.into(),
            created,
        });
        self
    }

    pub fn copilot_pane(
        mut self,
        id: &str,
        session: &str,
        window: u32,
        index: u32,
        pid: u32,
        title: &str,
    ) -> Self {
        self.panes.push(Pane {
            id: id.into(),
            session: session.into(),
            window,
            index,
            pid,
            title: title.into(),
        });
        self.processes.push((pid, 1, "bash".into()));
        self.processes.push((pid + 1, pid, "copilot".into()));
        self
    }

    pub fn ordinary_pane(
        mut self,
        id: &str,
        session: &str,
        window: u32,
        index: u32,
        pid: u32,
        title: &str,
    ) -> Self {
        self.panes.push(Pane {
            id: id.into(),
            session: session.into(),
            window,
            index,
            pid,
            title: title.into(),
        });
        self.processes.push((pid, 1, "bash".into()));
        self
    }

    pub fn process(mut self, pid: u32, parent: u32, command: &str) -> Self {
        self.processes.push((pid, parent, command.into()));
        self
    }

    pub fn now(mut self, now: i64) -> Self {
        self.now = now;
        self
    }

    pub fn env(mut self, name: &str, value: impl Into<String>) -> Self {
        self.extra_env.insert(name.into(), value.into());
        self
    }

    pub fn build(self) -> Self {
        self.sync();
        self
    }

    pub fn root(&self) -> &Path {
        self.temp.path()
    }

    pub fn state_dir(&self) -> PathBuf {
        self.root().join("state")
    }

    pub fn state_path(&self, pane: &str) -> PathBuf {
        self.state_dir()
            .join(format!("{}.json", pane.trim_start_matches('%')))
    }

    pub fn write_state(&self, pane: &str, status: &str) {
        self.write_state_value(
            pane,
            json!({
                "pane_id": pane,
                "session_id": "test",
                "status": status,
                "event": "test",
                "updated_at": "test",
                "updated_epoch": self.now
            }),
        );
    }

    pub fn write_done(&self, pane: &str, until: i64) {
        self.write_state_value(
            pane,
            json!({
                "pane_id": pane,
                "session_id": "test",
                "status": "idle",
                "event": "agentStop",
                "updated_at": "test",
                "updated_epoch": self.now,
                "flash": { "kind": "done", "until_epoch": until }
            }),
        );
    }

    pub fn write_state_value(&self, pane: &str, value: Value) {
        fs::write(
            self.state_path(pane),
            serde_json::to_vec(&value).expect("serialize state"),
        )
        .expect("write pane state");
    }

    pub fn read_state(&self, pane: &str) -> Value {
        serde_json::from_slice(&fs::read(self.state_path(pane)).expect("read pane state"))
            .expect("parse pane state")
    }

    pub fn command(&self) -> Command {
        self.sync();
        let mut command = Command::new(binary());
        command
            .env("FIXTURE_DIR", self.root())
            .env("AGENT_RADAR_STATE_DIR", self.state_dir())
            .env("TMUX_AGENT_ENGINE_STATE_DIR", self.state_dir())
            .env("TMUX_AGENT_ENGINE_TMUX_BIN", self.root().join("fake-tmux"))
            .env("TMUX_AGENT_ENGINE_PS_FILE", self.root().join("processes"))
            .env("TMUX_AGENT_ENGINE_NOW", self.now.to_string())
            .env("NO_COLOR", "1");
        for (name, value) in &self.extra_env {
            command.env(name, value);
        }
        command
    }

    pub fn run(&self, args: &[&str]) -> Output {
        let output = self.command().args(args).output().expect("run agent-radar");
        assert!(
            output.status.success(),
            "agent-radar {:?} failed\nstdout: {}\nstderr: {}",
            args,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        output
    }

    pub fn run_text(&self, args: &[&str]) -> String {
        String::from_utf8(self.run(args).stdout)
            .expect("utf8 stdout")
            .trim_end_matches('\n')
            .to_owned()
    }

    pub fn hook(&self, pane: &str, event: &str, payload: Value) {
        let mut command = self.command();
        command
            .args(["hook", event])
            .env("TMUX_PANE", pane)
            .env("TMUX_AGENT_STATUS_REFRESH", "0")
            .stdin(Stdio::piped());
        let mut child = command.spawn().expect("spawn hook");
        child
            .stdin
            .take()
            .expect("hook stdin")
            .write_all(
                serde_json::to_string(&payload)
                    .expect("serialize hook payload")
                    .as_bytes(),
            )
            .expect("write hook payload");
        let output = child.wait_with_output().expect("wait for hook");
        assert!(
            output.status.success(),
            "hook {event} failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    pub fn run_with_stdin(&self, args: &[&str], input: &str, env: &[(&str, &str)]) -> Output {
        let mut command = self.command();
        command.args(args).stdin(Stdio::piped());
        for (name, value) in env {
            command.env(name, value);
        }
        let mut child = command.spawn().expect("spawn agent-radar");
        child
            .stdin
            .take()
            .expect("agent-radar stdin")
            .write_all(input.as_bytes())
            .expect("write agent-radar stdin");
        let output = child.wait_with_output().expect("wait for agent-radar");
        assert!(
            output.status.success(),
            "agent-radar {:?} failed: {}",
            args,
            String::from_utf8_lossy(&output.stderr)
        );
        output
    }

    pub fn session_option(&self, session: &str) -> String {
        fs::read_to_string(self.root().join("options").join(session))
            .expect("read session status option")
    }

    pub fn tmux_calls(&self) -> String {
        fs::read_to_string(self.root().join("tmux-calls")).unwrap_or_default()
    }

    pub fn set_capture(&self, text: &str) {
        fs::write(self.root().join("capture"), text).expect("write capture fixture");
    }

    fn sync(&self) {
        let panes = self
            .panes
            .iter()
            .map(|pane| {
                format!(
                    "{}\t{}\t{}\t{}\t{}\t{}",
                    pane.id, pane.session, pane.window, pane.index, pane.pid, pane.title
                )
            })
            .collect::<Vec<_>>()
            .join("\n");
        fs::write(self.root().join("panes"), add_newline(&panes)).expect("write panes");

        let processes = self
            .processes
            .iter()
            .map(|(pid, parent, command)| format!("{pid} {parent} {command}"))
            .collect::<Vec<_>>()
            .join("\n");
        fs::write(self.root().join("processes"), add_newline(&processes)).expect("write processes");

        let sessions = self
            .sessions
            .iter()
            .map(|session| format!("{}\t{}", session.created, session.name))
            .collect::<Vec<_>>()
            .join("\n");
        fs::write(self.root().join("sessions"), add_newline(&sessions)).expect("write sessions");

        if !self.root().join("capture").exists() {
            fs::write(self.root().join("capture"), "").expect("write empty capture");
        }
    }
}

#[derive(Debug, Eq, PartialEq)]
pub struct AgentRow {
    pub rank: u8,
    pub pane: String,
    pub session: String,
    pub target: String,
    pub label: String,
    pub title: String,
}

pub fn parse_rows(output: &str) -> Vec<AgentRow> {
    output
        .lines()
        .filter_map(|line| {
            let fields: Vec<_> = line.splitn(7, '\t').collect();
            (fields.len() == 7).then(|| AgentRow {
                rank: fields[0].parse().expect("row rank"),
                pane: fields[1].into(),
                session: fields[2].into(),
                target: fields[3].into(),
                label: fields[4].into(),
                title: fields[5].into(),
            })
        })
        .collect()
}

pub struct StatusBar<'a>(&'a str);

impl<'a> StatusBar<'a> {
    pub fn new(value: &'a str) -> Self {
        Self(value)
    }

    pub fn has_icon_color(&self, color: &str) -> bool {
        self.0
            .starts_with(&format!("#[fg={color},bg=#24283b,bold] "))
    }

    pub fn has_pane(&self, target: &str, color: &str, completed: bool) -> bool {
        let label = if completed {
            format!("✓{target} ")
        } else {
            format!("{target} ")
        };
        self.0.contains(&format!("#[fg={color},bold]{label}"))
            || self.0.contains(&format!("#[fg={color},nobold]{label}"))
    }

    pub fn has_current_session(&self, label: &str, color: &str) -> bool {
        self.0
            .contains(&format!("#[fg=#050505,bg={color},bold] {label} #[default]"))
    }

    pub fn has_session_signal(&self, label: &str, color: &str) -> bool {
        self.0.contains(&format!("#[fg={color},bold]{label} "))
    }
}

pub fn binary() -> &'static str {
    env!("CARGO_BIN_EXE_agent-radar")
}

pub fn write_executable(path: &Path, contents: &str) {
    fs::write(path, contents).expect("write executable");
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).expect("chmod executable");
}

fn add_newline(value: &str) -> String {
    if value.is_empty() {
        String::new()
    } else {
        format!("{value}\n")
    }
}

const FAKE_TMUX: &str = r#"#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FIXTURE_DIR/tmux-calls"
command=$1
shift
case "$command" in
  list-panes)
    format=
    while [ $# -gt 0 ]; do
      if [ "$1" = -F ]; then format=$2; break; fi
      shift
    done
    case "$format" in
      *session_name*) cat "$FIXTURE_DIR/panes" ;;
      *) awk -F '\t' '{print $1 "\t" $5}' "$FIXTURE_DIR/panes" ;;
    esac
    ;;
  list-sessions)
    cat "$FIXTURE_DIR/sessions"
    ;;
  set-option)
    session=
    while [ $# -gt 0 ]; do
      case "$1" in
        -q) shift ;;
        -t) session=$2; shift 2 ;;
        @agent-radar-status)
          printf '%s' "$2" >"$FIXTURE_DIR/options/$session"
          exit 0
          ;;
        *) shift ;;
      esac
    done
    ;;
  show-option)
    [ -z "${SETUP_STATE_OPTION:-}" ] || printf '%s\n' "$SETUP_STATE_OPTION"
    ;;
  capture-pane)
    cat "$FIXTURE_DIR/capture"
    ;;
  switch-client|select-pane|run-shell|refresh-client)
    ;;
  *)
    printf 'unsupported fake tmux command: %s\n' "$command" >&2
    exit 1
    ;;
esac
"#;
