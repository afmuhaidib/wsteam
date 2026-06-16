use crate::config::{Config, GameEntry};
use crate::dxvk::DxvkManager;
use crate::error::{Result, WsteamError};
use crate::prefix::PrefixManager;
use crate::steam::SteamManager;
use crate::wine::WineEngine;
use std::path::PathBuf;
use std::process::Child;
use tracing::info;

pub struct Launcher {
    config: Config,
    wine: WineEngine,
}

impl Launcher {
    pub fn new(config: Config) -> Self {
        let wine = WineEngine::new(config.wine.wine_dir.clone());
        Self { config, wine }
    }

    pub fn steam_manager(&self) -> SteamManager {
        SteamManager::new(
            WineEngine::new(self.config.wine.wine_dir.clone()),
            self.config.steam.prefix_dir.clone(),
            self.config.data_dir.clone(),
        )
    }

    pub fn prefix_manager(&self) -> PrefixManager {
        PrefixManager::new(WineEngine::new(self.config.wine.wine_dir.clone()))
    }

    pub fn dxvk_manager(&self) -> DxvkManager {
        DxvkManager::new(
            WineEngine::new(self.config.wine.wine_dir.clone()),
            self.config.data_dir.clone(),
        )
    }

    pub fn wine_engine(&self) -> &WineEngine {
        &self.wine
    }

    /// Full environment check before launching any game
    pub fn verify_environment(&self) -> Result<()> {
        if !self.wine.is_installed() {
            return Err(WsteamError::WineNotFound(
                "Wine not installed. Run: wsteam setup wine".into(),
            ));
        }

        let steam = self.steam_manager();
        if !steam.is_installed() {
            return Err(WsteamError::SteamError(
                "Steam not installed. Run: wsteam setup steam".into(),
            ));
        }

        Ok(())
    }

    pub fn launch_steam(&self) -> Result<Child> {
        self.verify_environment()?;
        let steam = self.steam_manager();
        steam.launch_steam(&[])
    }

    pub fn launch_game_by_id(&self, app_id: u64) -> Result<Child> {
        self.verify_environment()?;

        if let Some(game) = self.config.games.iter().find(|g| g.app_id == app_id) {
            self.launch_game(game)
        } else {
            // Not in our library — try via Steam
            let steam = self.steam_manager();
            steam.launch_game(app_id)
        }
    }

    pub fn launch_game(&self, game: &GameEntry) -> Result<Child> {
        self.verify_environment()?;

        let prefix = game
            .prefix_override
            .clone()
            .unwrap_or_else(|| self.config.steam.prefix_dir.clone());

        if let Some(ref exe) = game.executable {
            let steam = self.steam_manager();
            steam.launch_game_exe(exe, game.app_id, &[])
        } else {
            let steam = self.steam_manager();
            steam.launch_game(game.app_id)
        }
    }

    pub fn scan_library(&self) -> Vec<crate::steam::InstalledGame> {
        let steam = self.steam_manager();
        steam.scan_games()
    }
}
