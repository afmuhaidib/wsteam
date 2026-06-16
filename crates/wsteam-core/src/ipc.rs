use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Commands sent from UI → daemon
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", content = "data")]
pub enum Command {
    GetStatus,
    SetupWine,
    SetupSteam,
    SetupDxvk,
    FullSetup,
    LaunchSteam,
    LaunchGame { app_id: u64 },
    ScanLibrary,
    GetConfig,
    KillWineserver,
    Shutdown,
}

/// Responses from daemon → UI
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "data")]
pub enum Response {
    Ok,
    Status(StatusPayload),
    Config(serde_json::Value),
    Library(Vec<GameInfo>),
    Progress { step: String, pct: u8 },
    Error { message: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusPayload {
    pub wine_installed: bool,
    pub wine_version: String,
    pub steam_installed: bool,
    pub dxvk_installed: bool,
    pub moltenvk_installed: bool,
    pub prefix_exists: bool,
    pub daemon_version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameInfo {
    pub app_id: u64,
    pub name: String,
    pub install_dir: PathBuf,
}

pub const SOCKET_PATH: &str = "/tmp/wsteam.sock";
pub const DAEMON_VERSION: &str = env!("CARGO_PKG_VERSION");
