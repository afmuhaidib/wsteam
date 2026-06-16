use crate::error::{Result, WsteamError};
use dirs::home_dir;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub data_dir: PathBuf,
    pub wine: WineConfig,
    pub steam: SteamConfig,
    pub dxvk: DxvkConfig,
    pub games: Vec<GameEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WineConfig {
    pub wine_dir: PathBuf,
    pub version: String,
    pub arch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SteamConfig {
    pub prefix_dir: PathBuf,
    pub installed: bool,
    pub steam_path: Option<PathBuf>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DxvkConfig {
    pub installed: bool,
    pub version: String,
    pub molten_vk_installed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameEntry {
    pub app_id: u64,
    pub name: String,
    pub install_dir: PathBuf,
    pub executable: Option<String>,
    pub last_played: Option<String>,
    pub play_time_secs: u64,
    pub prefix_override: Option<PathBuf>,
}

impl Default for Config {
    fn default() -> Self {
        let data_dir = home_dir()
            .unwrap_or_else(|| PathBuf::from("/tmp"))
            .join(".wsteam");

        Self {
            wine: WineConfig {
                wine_dir: data_dir.join("wine"),
                version: String::new(),
                arch: "x86_64".into(),
            },
            steam: SteamConfig {
                prefix_dir: data_dir.join("prefix"),
                installed: false,
                steam_path: None,
            },
            dxvk: DxvkConfig {
                installed: false,
                version: String::new(),
                molten_vk_installed: false,
            },
            games: Vec::new(),
            data_dir,
        }
    }
}

impl Config {
    pub fn load() -> Result<Self> {
        let path = config_path();
        if !path.exists() {
            return Ok(Self::default());
        }
        let raw = std::fs::read_to_string(&path)
            .map_err(|e| WsteamError::ConfigError(e.to_string()))?;
        toml::from_str(&raw).map_err(|e| WsteamError::ConfigError(e.to_string()))
    }

    pub fn save(&self) -> Result<()> {
        let path = config_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let raw = toml::to_string_pretty(self)
            .map_err(|e| WsteamError::ConfigError(e.to_string()))?;
        std::fs::write(&path, raw)?;
        Ok(())
    }

    pub fn data_dir(&self) -> &Path {
        &self.data_dir
    }

    pub fn add_or_update_game(&mut self, game: GameEntry) {
        if let Some(existing) = self.games.iter_mut().find(|g| g.app_id == game.app_id) {
            *existing = game;
        } else {
            self.games.push(game);
        }
    }
}

fn config_path() -> PathBuf {
    home_dir()
        .unwrap_or_else(|| PathBuf::from("/tmp"))
        .join(".wsteam")
        .join("config.toml")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_default_config() {
        let cfg = Config::default();
        assert!(!cfg.wine.wine_dir.to_string_lossy().is_empty());
        assert!(!cfg.steam.prefix_dir.to_string_lossy().is_empty());
        assert!(!cfg.steam.installed);
        assert!(!cfg.dxvk.installed);
        assert!(cfg.games.is_empty());
    }

    #[test]
    fn test_add_or_update_game() {
        let mut cfg = Config::default();
        let game = GameEntry {
            app_id: 945360,
            name: "Among Us".into(),
            install_dir: PathBuf::from("/tmp/Among Us"),
            executable: None,
            last_played: None,
            play_time_secs: 0,
            prefix_override: None,
        };
        cfg.add_or_update_game(game.clone());
        assert_eq!(cfg.games.len(), 1);
        assert_eq!(cfg.games[0].name, "Among Us");

        // Update existing
        let updated = GameEntry { play_time_secs: 3600, ..game };
        cfg.add_or_update_game(updated);
        assert_eq!(cfg.games.len(), 1);
        assert_eq!(cfg.games[0].play_time_secs, 3600);
    }

    #[test]
    fn test_save_and_load() {
        let tmp = tempfile::tempdir().unwrap();
        // We can't easily override the config_path, but we can test toml round-trip
        let cfg = Config::default();
        let raw = toml::to_string_pretty(&cfg).unwrap();
        let loaded: Config = toml::from_str(&raw).unwrap();
        assert_eq!(loaded.wine.arch, cfg.wine.arch);
    }
}
