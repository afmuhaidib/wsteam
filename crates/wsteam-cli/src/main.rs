use anyhow::Result;
use clap::{Parser, Subcommand};
use indicatif::{ProgressBar, ProgressStyle};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::net::UnixStream;
use wsteam_core::ipc::{Command, Response, SOCKET_PATH};

#[derive(Parser)]
#[command(name = "wsteam", about = "Run Windows Steam games on macOS", version)]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Run full setup (Wine + prefix + Steam + DXVK)
    Setup {
        #[arg(long, help = "Only install Wine")]
        wine_only: bool,
        #[arg(long, help = "Only install Steam")]
        steam_only: bool,
        #[arg(long, help = "Only install DXVK + MoltenVK")]
        dxvk_only: bool,
    },
    /// Show installation status
    Status,
    /// Launch Steam
    Steam,
    /// Launch a game by Steam App ID
    Launch {
        #[arg(help = "Steam App ID (e.g. 945360 for Among Us)")]
        app_id: u64,
    },
    /// List installed games
    List,
    /// Kill wineserver
    Kill,
    /// Start the wsteam daemon
    Daemon,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter("wsteam=warn")
        .init();

    let cli = Cli::parse();

    match cli.command {
        Cmd::Daemon => {
            eprintln!("Starting daemon... (run `wsteamd` directly instead)");
            std::process::Command::new("wsteamd").spawn()?.wait()?;
        }

        Cmd::Status => {
            let resp = send_command(Command::GetStatus).await?;
            match resp {
                Response::Status(s) => {
                    println!("wsteam status");
                    println!("  Wine:      {} (v{})", tick(s.wine_installed), s.wine_version);
                    println!("  Prefix:    {}", tick(s.prefix_exists));
                    println!("  Steam:     {}", tick(s.steam_installed));
                    println!("  DXVK:      {}", tick(s.dxvk_installed));
                    println!("  MoltenVK:  {}", tick(s.moltenvk_installed));
                    println!("  Daemon:    v{}", s.daemon_version);
                }
                Response::Error { message } => eprintln!("Error: {}", message),
                _ => {}
            }
        }

        Cmd::Setup { wine_only, steam_only, dxvk_only } => {
            let cmd = if wine_only {
                Command::SetupWine
            } else if steam_only {
                Command::SetupSteam
            } else if dxvk_only {
                Command::SetupDxvk
            } else {
                Command::FullSetup
            };

            println!("Running setup (this may take several minutes)...");
            let resp = send_command(cmd).await?;
            match resp {
                Response::Ok => println!("Setup complete!"),
                Response::Error { message } => eprintln!("Setup failed: {}", message),
                _ => {}
            }
        }

        Cmd::Steam => {
            println!("Launching Steam...");
            let resp = send_command(Command::LaunchSteam).await?;
            handle_simple_response(resp);
        }

        Cmd::Launch { app_id } => {
            println!("Launching app {}...", app_id);
            let resp = send_command(Command::LaunchGame { app_id }).await?;
            handle_simple_response(resp);
        }

        Cmd::List => {
            let resp = send_command(Command::ScanLibrary).await?;
            match resp {
                Response::Library(games) => {
                    if games.is_empty() {
                        println!("No games found. Install games via Steam first.");
                    } else {
                        println!("{:<12} {}", "App ID", "Name");
                        println!("{}", "-".repeat(40));
                        for g in &games {
                            println!("{:<12} {}", g.app_id, g.name);
                        }
                    }
                }
                Response::Error { message } => eprintln!("Error: {}", message),
                _ => {}
            }
        }

        Cmd::Kill => {
            let resp = send_command(Command::KillWineserver).await?;
            handle_simple_response(resp);
        }
    }

    Ok(())
}

async fn send_command(cmd: Command) -> Result<Response> {
    let stream = UnixStream::connect(SOCKET_PATH).await.map_err(|_| {
        anyhow::anyhow!(
            "Cannot connect to daemon. Run `wsteamd` first."
        )
    })?;

    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    let mut json = serde_json::to_string(&cmd)?;
    json.push('\n');
    writer.write_all(json.as_bytes()).await?;

    if let Some(line) = lines.next_line().await? {
        let resp: Response = serde_json::from_str(&line)?;
        Ok(resp)
    } else {
        Err(anyhow::anyhow!("Daemon closed connection"))
    }
}

fn tick(v: bool) -> &'static str {
    if v { "✓" } else { "✗" }
}

fn handle_simple_response(resp: Response) {
    match resp {
        Response::Ok => println!("OK"),
        Response::Error { message } => eprintln!("Error: {}", message),
        _ => {}
    }
}
