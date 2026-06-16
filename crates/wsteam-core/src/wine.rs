use crate::error::{Result, WsteamError};
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::{info, warn};

// gcenx provides Wine bottles that work on macOS Apple Silicon via Rosetta 2
// We use Wine Crossover build which has best Steam/game compat
const WINE_CROSSOVER_URL: &str =
    "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.10/wine-staging-11.10-osx64.tar.xz";
const WINE_CROSSOVER_VERSION: &str = "11.10";

pub struct WineEngine {
    wine_dir: PathBuf,
}

impl WineEngine {
    pub fn new(wine_dir: PathBuf) -> Self {
        Self { wine_dir }
    }

    pub fn wine_bin(&self) -> PathBuf {
        self.wine_dir.join("bin").join("wine64")
    }

    pub fn wine32_bin(&self) -> PathBuf {
        self.wine_dir.join("bin").join("wine")
    }

    pub fn server_bin(&self) -> PathBuf {
        self.wine_dir.join("bin").join("wineserver")
    }

    pub fn is_installed(&self) -> bool {
        self.wine_bin().exists() || self.wine32_bin().exists()
    }

    pub fn version(&self) -> String {
        WINE_CROSSOVER_VERSION.to_string()
    }

    pub async fn install(&self, progress_cb: impl Fn(u64, u64) + Send + 'static) -> Result<()> {
        if self.is_installed() {
            info!("Wine already installed at {:?}", self.wine_dir);
            return Ok(());
        }

        std::fs::create_dir_all(&self.wine_dir)?;

        info!("Downloading Wine Crossover {}...", WINE_CROSSOVER_VERSION);
        let archive = self.wine_dir.parent().unwrap().join("wine.tar.xz");
        download_file(WINE_CROSSOVER_URL, &archive, progress_cb).await?;

        info!("Extracting Wine...");
        self.extract_wine(&archive)?;

        std::fs::remove_file(&archive).ok();
        info!("Wine installed at {:?}", self.wine_dir);
        Ok(())
    }

    fn extract_wine(&self, archive: &Path) -> Result<()> {
        let parent = self.wine_dir.parent().unwrap();
        let status = Command::new("tar")
            .args(["-xJf", archive.to_str().unwrap(), "-C", parent.to_str().unwrap()])
            .status()?;

        if !status.success() {
            return Err(WsteamError::WineNotFound(
                "tar extraction failed".into(),
            ));
        }

        // gcenx tarballs extract to "wine-crossover-VERSION" folder — rename to "wine"
        let extracted_name = format!("wine-staging-{}", WINE_CROSSOVER_VERSION);
        let extracted = parent.join(&extracted_name);
        if extracted.exists() && extracted != self.wine_dir {
            std::fs::rename(&extracted, &self.wine_dir)?;
        }

        // Some builds extract a .app bundle
        let app_bundle = parent.join(format!("Wine Staging.app"));
        if app_bundle.exists() {
            let contents = app_bundle.join("Contents").join("Resources").join("wine");
            if contents.exists() {
                if self.wine_dir.exists() {
                    std::fs::remove_dir_all(&self.wine_dir).ok();
                }
                std::fs::rename(&contents, &self.wine_dir)?;
            }
        }

        Ok(())
    }

    pub fn run_wine(
        &self,
        prefix_dir: &Path,
        exe: &str,
        args: &[&str],
        env_overrides: &[(&str, &str)],
    ) -> Result<std::process::Child> {
        let wine_bin = if self.wine_bin().exists() {
            self.wine_bin()
        } else {
            self.wine32_bin()
        };

        if !wine_bin.exists() {
            return Err(WsteamError::WineNotFound(
                wine_bin.to_string_lossy().into_owned(),
            ));
        }

        let mut cmd = Command::new(&wine_bin);
        cmd.arg(exe);
        cmd.args(args);
        cmd.env("WINEPREFIX", prefix_dir);
        cmd.env("WINEDEBUG", "-all");
        cmd.env("WINE_HIDE_NVIDIA_GPU", "1");

        // MoltenVK Vulkan ICD
        let icd_path = self.wine_dir.parent().unwrap().join("MoltenVK").join("MoltenVK_icd.json");
        if icd_path.exists() {
            cmd.env("VK_ICD_FILENAMES", &icd_path);
        }

        // DXVK async
        cmd.env("DXVK_ASYNC", "1");
        cmd.env("DXVK_STATE_CACHE", "1");

        for (k, v) in env_overrides {
            cmd.env(k, v);
        }

        let child = cmd.spawn()?;
        Ok(child)
    }

    pub fn run_wine_wait(
        &self,
        prefix_dir: &Path,
        exe: &str,
        args: &[&str],
        env_overrides: &[(&str, &str)],
    ) -> Result<()> {
        let mut child = self.run_wine(prefix_dir, exe, args, env_overrides)?;
        let status = child.wait()?;
        if !status.success() {
            warn!("Wine process exited with: {:?}", status);
        }
        Ok(())
    }

    pub fn kill_wineserver(&self, prefix_dir: &Path) {
        let _ = Command::new(self.server_bin())
            .env("WINEPREFIX", prefix_dir)
            .arg("-k")
            .status();
    }
}

pub(crate) async fn download_file(
    url: &str,
    dest: &Path,
    progress_cb: impl Fn(u64, u64),
) -> Result<()> {
    use futures::StreamExt;

    let client = reqwest::Client::builder()
        .user_agent("wsteam/0.1")
        .build()?;
    let resp = client.get(url).send().await?;

    if !resp.status().is_success() {
        return Err(WsteamError::DownloadFailed(
            format!("HTTP {}", resp.status()),
        ));
    }

    let total = resp.content_length().unwrap_or(0);
    let mut stream = resp.bytes_stream();
    let mut file = tokio::fs::File::create(dest).await
        .map_err(|e| WsteamError::Io(e))?;
    let mut downloaded = 0u64;

    use tokio::io::AsyncWriteExt;
    while let Some(chunk) = stream.next().await {
        let chunk = chunk?;
        file.write_all(&chunk).await.map_err(|e| WsteamError::Io(e))?;
        downloaded += chunk.len() as u64;
        progress_cb(downloaded, total);
    }

    Ok(())
}


