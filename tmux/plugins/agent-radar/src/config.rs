use std::env;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
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

pub(crate) fn env_i64(name: &str) -> Option<i64> {
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
