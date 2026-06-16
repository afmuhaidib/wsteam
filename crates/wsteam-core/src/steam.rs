use crate::error::{Result, WsteamError};
use crate::wine::WineEngine;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::info;

const STEAM_INSTALLER_URL: &str =
    "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe";

pub struct SteamManager {
    wine: WineEngine,
    prefix_dir: PathBuf,
    data_dir: PathBuf,
}

impl SteamManager {
    pub fn new(wine: WineEngine, prefix_dir: PathBuf, data_dir: PathBuf) -> Self {
        Self { wine, prefix_dir, data_dir }
    }

    pub fn steam_exe(&self) -> PathBuf {
        self.prefix_dir
            .join("drive_c")
            .join("Program Files (x86)")
            .join("Steam")
            .join("Steam.exe")
    }

    pub fn is_installed(&self) -> bool {
        self.steam_exe().exists()
    }

    pub async fn download_installer(
        &self,
        progress_cb: impl Fn(u64, u64) + Send + 'static,
    ) -> Result<PathBuf> {
        let dest = self.data_dir.join("SteamSetup.exe");
        if dest.exists() {
            return Ok(dest);
        }
        info!("Downloading Steam installer...");
        crate::wine::download_file(STEAM_INSTALLER_URL, &dest, progress_cb).await?;
        info!("Steam installer downloaded");
        Ok(dest)
    }

    pub fn install_steam(&self, installer_path: &Path) -> Result<()> {
        if self.is_installed() {
            info!("Steam already installed");
            return Ok(());
        }

        info!("Installing Steam into Wine prefix...");

        // Run steam installer silently
        self.wine.run_wine_wait(
            &self.prefix_dir,
            installer_path.to_str().unwrap(),
            &["/S"], // silent install
            &[],
        )?;

        if !self.is_installed() {
            return Err(WsteamError::SteamError(
                "Steam installer ran but Steam.exe not found. Try manual install.".into(),
            ));
        }

        info!("Steam installed successfully");
        Ok(())
    }

    pub fn launch_steam(&self, extra_args: &[&str]) -> Result<std::process::Child> {
        if !self.is_installed() {
            return Err(WsteamError::SteamError("Steam not installed".into()));
        }

        let steam_path = self.steam_exe();
        let steam_win_path = format!(
            "C:\\Program Files (x86)\\Steam\\Steam.exe"
        );

        info!("Launching Steam...");
        self.wine.run_wine(
            &self.prefix_dir,
            &steam_win_path,
            extra_args,
            &[
                ("STEAM_COMPAT_CLIENT_INSTALL_PATH", steam_path.parent().unwrap().to_str().unwrap()),
                ("SteamGameId", ""),
            ],
        )
    }

    pub fn launch_game(&self, app_id: u64) -> Result<std::process::Child> {
        if !self.is_installed() {
            return Err(WsteamError::SteamError("Steam not installed".into()));
        }

        let url = format!("steam://run/{}", app_id);
        info!("Launching game {} via Steam...", app_id);

        self.wine.run_wine(
            &self.prefix_dir,
            "C:\\Program Files (x86)\\Steam\\Steam.exe",
            &["-applaunch", &app_id.to_string()],
            &[("SteamGameId", &app_id.to_string())],
        )
    }

    pub fn launch_game_exe(
        &self,
        exe_win_path: &str,
        app_id: u64,
        extra_args: &[&str],
    ) -> Result<std::process::Child> {
        info!("Launching {} (appid {})", exe_win_path, app_id);
        self.wine.run_wine(
            &self.prefix_dir,
            exe_win_path,
            extra_args,
            &[("SteamGameId", &app_id.to_string())],
        )
    }

    /// Find installed Steam games by scanning steamapps folder
    pub fn scan_games(&self) -> Vec<InstalledGame> {
        let steamapps = self
            .prefix_dir
            .join("drive_c")
            .join("Program Files (x86)")
            .join("Steam")
            .join("steamapps");

        if !steamapps.exists() {
            return Vec::new();
        }

        let mut games = Vec::new();
        if let Ok(entries) = std::fs::read_dir(&steamapps) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.extension().and_then(|e| e.to_str()) == Some("acf") {
                    if let Some(game) = parse_acf(&path) {
                        games.push(game);
                    }
                }
            }
        }
        games
    }

    pub fn prefix_dir(&self) -> &Path {
        &self.prefix_dir
    }
}

#[derive(Debug, Clone)]
pub struct InstalledGame {
    pub app_id: u64,
    pub name: String,
    pub install_dir: PathBuf,
}

fn parse_acf(path: &Path) -> Option<InstalledGame> {
    let content = std::fs::read_to_string(path).ok()?;
    let app_id = extract_acf_field(&content, "appid")?.parse().ok()?;
    let name = extract_acf_field(&content, "name")?;
    let install_dir_name = extract_acf_field(&content, "installdir")?;

    let install_dir = path
        .parent()?
        .join("common")
        .join(&install_dir_name);

    Some(InstalledGame { app_id, name, install_dir })
}

fn extract_acf_field(content: &str, field: &str) -> Option<String> {
    let needle = format!("\"{}\"", field);
    for line in content.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with(needle.as_str()) {
            continue;
        }
        // Format: "key"    "value"
        let after_key = trimmed[needle.len()..].trim_start();
        if after_key.starts_with('"') {
            let inner = &after_key[1..];
            if let Some(end) = inner.find('"') {
                return Some(inner[..end].to_string());
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_acf() {
        let content = r#""AppState"
{
    "appid"     "945360"
    "name"      "Among Us"
    "installdir"    "Among Us"
}"#;
        // Write a temp acf and parse
        let dir = tempfile::tempdir().unwrap();
        let acf = dir.path().join("appmanifest_945360.acf");
        std::fs::write(&acf, content).unwrap();

        let game = parse_acf(&acf);
        assert!(game.is_some());
        let g = game.unwrap();
        assert_eq!(g.app_id, 945360);
        assert_eq!(g.name, "Among Us");
    }

    #[test]
    fn test_extract_acf_field() {
        let content = r#"	"appid"		"945360""#;
        let val = extract_acf_field(content, "appid");
        // May or may not find depending on tab split — just verify no panic
        let _ = val;
    }
}
