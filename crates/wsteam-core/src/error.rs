use thiserror::Error;

#[derive(Error, Debug)]
pub enum WsteamError {
    #[error("Wine not found: {0}")]
    WineNotFound(String),
    #[error("Prefix error: {0}")]
    PrefixError(String),
    #[error("Download failed: {0}")]
    DownloadFailed(String),
    #[error("Steam error: {0}")]
    SteamError(String),
    #[error("Launch error: {0}")]
    LaunchError(String),
    #[error("Config error: {0}")]
    ConfigError(String),
    #[error("DXVK error: {0}")]
    DxvkError(String),
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

pub type Result<T> = std::result::Result<T, WsteamError>;
