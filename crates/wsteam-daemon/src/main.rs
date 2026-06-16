use anyhow::Result;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::{UnixListener, UnixStream};
use tokio::sync::Mutex;
use tracing::{error, info, warn};
use wsteam_core::{
    config::Config,
    dxvk::DxvkManager,
    ipc::{Command, GameInfo, Response, StatusPayload, SOCKET_PATH},
    launcher::Launcher,
    prefix::PrefixManager,
    steam::SteamManager,
    wine::WineEngine,
};

type SharedConfig = Arc<Mutex<Config>>;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("wsteam=info".parse()?),
        )
        .init();

    // Remove stale socket
    let _ = std::fs::remove_file(SOCKET_PATH);

    let listener = UnixListener::bind(SOCKET_PATH)?;
    info!("wsteamd listening on {}", SOCKET_PATH);

    let config = Config::load().unwrap_or_default();
    std::fs::create_dir_all(&config.data_dir)?;
    let shared = Arc::new(Mutex::new(config));

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let cfg = Arc::clone(&shared);
                tokio::spawn(async move {
                    if let Err(e) = handle_client(stream, cfg).await {
                        error!("Client error: {}", e);
                    }
                });
            }
            Err(e) => error!("Accept error: {}", e),
        }
    }
}

async fn handle_client(stream: UnixStream, cfg: SharedConfig) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }

        let cmd: Command = match serde_json::from_str(&line) {
            Ok(c) => c,
            Err(e) => {
                let resp = Response::Error { message: e.to_string() };
                send_response(&mut writer, &resp).await?;
                continue;
            }
        };

        info!("Command: {:?}", cmd);
        let response = dispatch(cmd, Arc::clone(&cfg)).await;
        send_response(&mut writer, &response).await?;
    }

    Ok(())
}

async fn send_response(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    resp: &Response,
) -> Result<()> {
    let mut json = serde_json::to_string(resp)?;
    json.push('\n');
    writer.write_all(json.as_bytes()).await?;
    Ok(())
}

async fn dispatch(cmd: Command, shared: SharedConfig) -> Response {
    match cmd {
        Command::GetStatus => {
            let cfg = shared.lock().await.clone();
            let wine = WineEngine::new(cfg.wine.wine_dir.clone());
            let steam = SteamManager::new(
                WineEngine::new(cfg.wine.wine_dir.clone()),
                cfg.steam.prefix_dir.clone(),
                cfg.data_dir.clone(),
            );
            let dxvk = DxvkManager::new(
                WineEngine::new(cfg.wine.wine_dir.clone()),
                cfg.data_dir.clone(),
            );

            Response::Status(StatusPayload {
                wine_installed: wine.is_installed(),
                wine_version: wine.version(),
                steam_installed: steam.is_installed(),
                dxvk_installed: dxvk.is_dxvk_installed(),
                moltenvk_installed: dxvk.is_moltenvk_installed(),
                prefix_exists: cfg.steam.prefix_dir.join("system.reg").exists(),
                daemon_version: wsteam_core::ipc::DAEMON_VERSION.into(),
            })
        }

        Command::SetupWine => {
            let cfg = shared.lock().await.clone();
            let wine = WineEngine::new(cfg.wine.wine_dir.clone());

            match wine.install(|d, t| {
                let pct = if t > 0 { (d * 100 / t) as u8 } else { 0 };
                info!("Wine download: {}%", pct);
            }).await {
                Ok(()) => {
                    let mut locked = shared.lock().await;
                    locked.wine.version = wine.version();
                    locked.save().ok();
                    Response::Ok
                }
                Err(e) => Response::Error { message: e.to_string() },
            }
        }

        Command::SetupSteam => {
            let cfg = shared.lock().await.clone();
            let steam = SteamManager::new(
                WineEngine::new(cfg.wine.wine_dir.clone()),
                cfg.steam.prefix_dir.clone(),
                cfg.data_dir.clone(),
            );
            let prefix_mgr = PrefixManager::new(WineEngine::new(cfg.wine.wine_dir.clone()));

            // Ensure prefix exists
            if let Err(e) = prefix_mgr.create_prefix(&cfg.steam.prefix_dir) {
                return Response::Error { message: format!("Prefix creation failed: {}", e) };
            }

            match steam.download_installer(|d, t| {
                let pct = if t > 0 { (d * 100 / t) as u8 } else { 0 };
                info!("Steam download: {}%", pct);
            }).await {
                Ok(installer) => {
                    match steam.install_steam(&installer) {
                        Ok(()) => {
                            let mut locked = shared.lock().await;
                            locked.steam.installed = true;
                            locked.steam.steam_path = Some(steam.steam_exe());
                            locked.save().ok();
                            Response::Ok
                        }
                        Err(e) => Response::Error { message: e.to_string() },
                    }
                }
                Err(e) => Response::Error { message: e.to_string() },
            }
        }

        Command::SetupDxvk => {
            let cfg = shared.lock().await.clone();
            let dxvk = DxvkManager::new(
                WineEngine::new(cfg.wine.wine_dir.clone()),
                cfg.data_dir.clone(),
            );

            let r1 = dxvk.install_dxvk(|d, t| {
                info!("DXVK download: {}/{}", d, t);
            }).await;

            let r2 = dxvk.install_moltenvk(|d, t| {
                info!("MoltenVK download: {}/{}", d, t);
            }).await;

            if let Err(e) = r1.and(r2) {
                return Response::Error { message: e.to_string() };
            }

            if let Err(e) = dxvk.install_into_prefix(&cfg.steam.prefix_dir) {
                return Response::Error { message: format!("DXVK prefix install: {}", e) };
            }

            let mut locked = shared.lock().await;
            locked.dxvk.installed = true;
            locked.dxvk.version = DxvkManager::version().into();
            locked.dxvk.molten_vk_installed = true;
            locked.save().ok();
            Response::Ok
        }

        Command::FullSetup => {
            // Inline all steps to avoid recursive async calls
            let steps: Vec<Command> = vec![
                Command::SetupWine,
                Command::SetupSteam,
                Command::SetupDxvk,
            ];
            for step in steps {
                let r = Box::pin(dispatch(step, Arc::clone(&shared))).await;
                if let Response::Error { message } = r {
                    return Response::Error { message };
                }
            }
            Response::Ok
        }

        Command::LaunchSteam => {
            let cfg = shared.lock().await.clone();
            let launcher = Launcher::new(cfg);
            match launcher.launch_steam() {
                Ok(_child) => Response::Ok,
                Err(e) => Response::Error { message: e.to_string() },
            }
        }

        Command::LaunchGame { app_id } => {
            let cfg = shared.lock().await.clone();
            let launcher = Launcher::new(cfg);
            match launcher.launch_game_by_id(app_id) {
                Ok(_child) => Response::Ok,
                Err(e) => Response::Error { message: e.to_string() },
            }
        }

        Command::ScanLibrary => {
            let cfg = shared.lock().await.clone();
            let launcher = Launcher::new(cfg);
            let games = launcher.scan_library();
            let infos = games
                .into_iter()
                .map(|g| GameInfo {
                    app_id: g.app_id,
                    name: g.name,
                    install_dir: g.install_dir,
                })
                .collect();
            Response::Library(infos)
        }

        Command::GetConfig => {
            let cfg = shared.lock().await.clone();
            match serde_json::to_value(&cfg) {
                Ok(v) => Response::Config(v),
                Err(e) => Response::Error { message: e.to_string() },
            }
        }

        Command::KillWineserver => {
            let cfg = shared.lock().await.clone();
            let wine = WineEngine::new(cfg.wine.wine_dir.clone());
            wine.kill_wineserver(&cfg.steam.prefix_dir);
            Response::Ok
        }

        Command::Shutdown => {
            info!("Daemon shutting down");
            std::process::exit(0);
        }
    }
}
