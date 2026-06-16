use crate::error::{Result, WsteamError};
use crate::wine::WineEngine;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::info;

pub struct PrefixManager {
    wine: WineEngine,
}

impl PrefixManager {
    pub fn new(wine: WineEngine) -> Self {
        Self { wine }
    }

    /// Create a new 64-bit Windows 10 Wine prefix
    pub fn create_prefix(&self, prefix_dir: &Path) -> Result<()> {
        if prefix_dir.join("system.reg").exists() {
            info!("Prefix already exists at {:?}", prefix_dir);
            return Ok(());
        }

        std::fs::create_dir_all(prefix_dir)?;
        info!("Creating Wine prefix at {:?}", prefix_dir);

        // WINEARCH=win64 creates a 64-bit prefix
        let wine_bin = if self.wine.wine_bin().exists() {
            self.wine.wine_bin()
        } else {
            self.wine.wine32_bin()
        };

        let status = Command::new(&wine_bin)
            .arg("wineboot")
            .arg("--init")
            .env("WINEPREFIX", prefix_dir)
            .env("WINEARCH", "win64")
            .env("WINEDEBUG", "-all")
            .env("DISPLAY", "") // suppress X11 on macOS
            .status()?;

        if !status.success() {
            return Err(WsteamError::PrefixError("wineboot --init failed".into()));
        }

        // Set Windows version to Windows 10
        self.set_windows_version(prefix_dir, "win10")?;

        info!("Prefix created successfully");
        Ok(())
    }

    pub fn set_windows_version(&self, prefix_dir: &Path, version: &str) -> Result<()> {
        let wine_bin = if self.wine.wine_bin().exists() {
            self.wine.wine_bin()
        } else {
            self.wine.wine32_bin()
        };

        Command::new(&wine_bin)
            .args(["winecfg", "-v", version])
            .env("WINEPREFIX", prefix_dir)
            .env("WINEDEBUG", "-all")
            .status()?;

        Ok(())
    }

    /// Install a Windows DLL override (native,builtin or builtin,native)
    pub fn add_dll_override(
        &self,
        prefix_dir: &Path,
        dll_name: &str,
        mode: &str,
    ) -> Result<()> {
        let wine_bin = if self.wine.wine_bin().exists() {
            self.wine.wine_bin()
        } else {
            self.wine.wine32_bin()
        };

        let key = format!(
            r"HKEY_CURRENT_USER\Software\Wine\DllOverrides"
        );
        let cmd = format!(
            r#"reg add "{}" /v "{}" /d "{}" /f"#,
            key, dll_name, mode
        );

        Command::new(&wine_bin)
            .args(["cmd", "/c", &cmd])
            .env("WINEPREFIX", prefix_dir)
            .env("WINEDEBUG", "-all")
            .status()?;

        Ok(())
    }

    pub fn drive_c(&self, prefix_dir: &Path) -> PathBuf {
        prefix_dir.join("drive_c")
    }

    pub fn program_files(&self, prefix_dir: &Path) -> PathBuf {
        self.drive_c(prefix_dir)
            .join("Program Files (x86)")
    }

    pub fn program_files_64(&self, prefix_dir: &Path) -> PathBuf {
        self.drive_c(prefix_dir).join("Program Files")
    }

    pub fn temp_dir(&self, prefix_dir: &Path) -> PathBuf {
        self.drive_c(prefix_dir)
            .join("windows")
            .join("temp")
    }

    /// Copy a file into the prefix's Windows/temp folder
    pub fn copy_to_temp(&self, prefix_dir: &Path, src: &Path) -> Result<PathBuf> {
        let tmp = self.temp_dir(prefix_dir);
        std::fs::create_dir_all(&tmp)?;
        let dest = tmp.join(src.file_name().unwrap());
        std::fs::copy(src, &dest)?;
        Ok(dest)
    }

    /// Convert a Unix path inside the prefix to a Windows drive path
    pub fn to_windows_path(&self, prefix_dir: &Path, unix_path: &Path) -> Option<String> {
        let drive_c = self.drive_c(prefix_dir);
        unix_path
            .strip_prefix(&drive_c)
            .ok()
            .map(|rel| format!("C:\\{}", rel.to_string_lossy().replace('/', "\\")))
    }
}
