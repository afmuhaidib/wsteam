use crate::error::{Result, WsteamError};
use crate::wine::WineEngine;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::info;

// DXVK 2.x - translates DX9/10/11 → Vulkan → Metal (via MoltenVK)
const DXVK_VERSION: &str = "2.5.3";
const DXVK_URL: &str =
    "https://github.com/Gcenx/DXVK-macOS/releases/download/v2.5.3/dxvk-macOS-v2.5.3.tar.gz";

// MoltenVK provides Vulkan on Metal
const MOLTENVK_VERSION: &str = "1.2.11";
const MOLTENVK_URL: &str =
    "https://github.com/KhronosGroup/MoltenVK/releases/download/v1.2.11/MoltenVK-macos.tar";

pub struct DxvkManager {
    wine: WineEngine,
    data_dir: PathBuf,
}

impl DxvkManager {
    pub fn new(wine: WineEngine, data_dir: PathBuf) -> Self {
        Self { wine, data_dir }
    }

    pub fn dxvk_dir(&self) -> PathBuf {
        self.data_dir.join("dxvk")
    }

    pub fn moltenvk_dir(&self) -> PathBuf {
        self.data_dir.join("MoltenVK")
    }

    pub fn is_dxvk_installed(&self) -> bool {
        self.dxvk_dir().join("x64").join("d3d11.dll").exists()
    }

    pub fn is_moltenvk_installed(&self) -> bool {
        self.moltenvk_dir().join("MoltenVK_icd.json").exists()
    }

    pub async fn install_dxvk(
        &self,
        progress_cb: impl Fn(u64, u64) + Send + 'static,
    ) -> Result<()> {
        if self.is_dxvk_installed() {
            info!("DXVK already installed");
            return Ok(());
        }

        std::fs::create_dir_all(self.dxvk_dir())?;
        let archive = self.data_dir.join("dxvk.tar.gz");

        info!("Downloading DXVK {}...", DXVK_VERSION);
        crate::wine::download_file(DXVK_URL, &archive, progress_cb).await?;

        info!("Extracting DXVK...");
        let status = Command::new("tar")
            .args([
                "-xzf",
                archive.to_str().unwrap(),
                "-C",
                self.data_dir.to_str().unwrap(),
            ])
            .status()?;

        if !status.success() {
            return Err(WsteamError::DxvkError("DXVK extraction failed".into()));
        }

        // Rename extracted dir to "dxvk"
        let extracted = self.data_dir.join(format!("dxvk-macOS-v{}", DXVK_VERSION));
        if extracted.exists() {
            if self.dxvk_dir().exists() {
                std::fs::remove_dir_all(self.dxvk_dir())?;
            }
            std::fs::rename(&extracted, self.dxvk_dir())?;
        }

        std::fs::remove_file(&archive).ok();
        info!("DXVK installed");
        Ok(())
    }

    pub async fn install_moltenvk(
        &self,
        progress_cb: impl Fn(u64, u64) + Send + 'static,
    ) -> Result<()> {
        if self.is_moltenvk_installed() {
            info!("MoltenVK already installed");
            return Ok(());
        }

        std::fs::create_dir_all(self.moltenvk_dir())?;
        let archive = self.data_dir.join("moltenvk.tar");

        info!("Downloading MoltenVK {}...", MOLTENVK_VERSION);
        crate::wine::download_file(MOLTENVK_URL, &archive, progress_cb).await?;

        info!("Extracting MoltenVK...");
        let status = Command::new("tar")
            .args([
                "-xf",
                archive.to_str().unwrap(),
                "-C",
                self.data_dir.to_str().unwrap(),
            ])
            .status()?;

        if !status.success() {
            return Err(WsteamError::DxvkError("MoltenVK extraction failed".into()));
        }

        // Copy MoltenVK ICD and dylib to our MoltenVK dir
        self.setup_moltenvk_icd()?;

        std::fs::remove_file(&archive).ok();
        info!("MoltenVK installed");
        Ok(())
    }

    fn setup_moltenvk_icd(&self) -> Result<()> {
        // MoltenVK tar extracts to MoltenVK/ folder
        let extracted = self.data_dir.join("MoltenVK");

        // Find the dylib
        let dylib_path = extracted
            .join("MoltenVK")
            .join("dylib")
            .join("macOS")
            .join("libMoltenVK.dylib");

        if !dylib_path.exists() {
            // Try alternate layout
            return Ok(());
        }

        let dest_dylib = self.moltenvk_dir().join("libMoltenVK.dylib");
        std::fs::copy(&dylib_path, &dest_dylib)?;

        // Write ICD JSON
        let icd_json = serde_json::json!({
            "file_format_version": "1.0.0",
            "ICD": {
                "library_path": dest_dylib.to_str().unwrap(),
                "api_version": "1.3.0"
            }
        });

        let icd_path = self.moltenvk_dir().join("MoltenVK_icd.json");
        std::fs::write(&icd_path, serde_json::to_string_pretty(&icd_json)?)?;

        Ok(())
    }

    /// Install DXVK DLLs into a Wine prefix
    pub fn install_into_prefix(&self, prefix_dir: &Path) -> Result<()> {
        if !self.is_dxvk_installed() {
            return Err(WsteamError::DxvkError("DXVK not downloaded yet".into()));
        }

        let system32 = prefix_dir
            .join("drive_c")
            .join("windows")
            .join("system32");
        let syswow64 = prefix_dir
            .join("drive_c")
            .join("windows")
            .join("syswow64");

        std::fs::create_dir_all(&system32)?;
        std::fs::create_dir_all(&syswow64)?;

        let dlls_64 = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"];
        let dlls_32 = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"];

        // Install x64 DLLs
        for dll in &dlls_64 {
            let src = self.dxvk_dir().join("x64").join(dll);
            if src.exists() {
                std::fs::copy(&src, system32.join(dll))?;
                info!("Installed {} (x64)", dll);
            }
        }

        // Install x32 DLLs
        for dll in &dlls_32 {
            let src = self.dxvk_dir().join("x32").join(dll);
            if src.exists() {
                std::fs::copy(&src, syswow64.join(dll))?;
                info!("Installed {} (x32)", dll);
            }
        }

        // Set DLL overrides in registry
        self.set_dxvk_registry_overrides(prefix_dir)?;

        info!("DXVK installed into prefix");
        Ok(())
    }

    fn set_dxvk_registry_overrides(&self, prefix_dir: &Path) -> Result<()> {
        let wine_bin = if self.wine.wine_bin().exists() {
            self.wine.wine_bin()
        } else {
            self.wine.wine32_bin()
        };

        let dlls = ["d3d9", "d3d10core", "d3d11", "dxgi"];
        for dll in &dlls {
            let key = r"HKEY_CURRENT_USER\Software\Wine\DllOverrides";
            let cmd = format!(r#"reg add "{}" /v "{}" /d "native,builtin" /f"#, key, dll);
            Command::new(&wine_bin)
                .args(["cmd", "/c", &cmd])
                .env("WINEPREFIX", prefix_dir)
                .env("WINEDEBUG", "-all")
                .status()
                .ok();
        }

        Ok(())
    }

    pub fn version() -> &'static str {
        DXVK_VERSION
    }
}
