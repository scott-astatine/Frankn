use clap::{Parser, Subcommand};

mod utils;
mod app;
mod capabilities;
mod platform;
mod auth;
mod config;
mod signaling;
mod transport;

// Compatibility re-exports for child modules
pub use transport::protocol::messages::{ClientMessage, HostMessage, Status};

#[derive(Parser)]
#[command(name = "frankn-host")]
#[command(about = "Frankn Personal Remote Ops Center Host", long_about = None)]
struct Cli {
    /// Path to a custom configuration file
    #[arg(short, long, value_name = "FILE")]
    config: Option<String>,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand)]
enum Commands {
    /// Configure host settings
    Config,
    /// Display pairing ID and QR code
    Pair,
    /// Run as a separate Dohee worker process (stdio IPC)
    DoheeWorker {
        #[arg(long)]
        model: String,
    },
    /// Detect, inspect and report status of video capture devices (/dev/video*)
    ProbeCamera,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    let cli = Cli::parse();
    let custom_path = cli.config.map(std::path::PathBuf::from);

    // Load config or initialize on first run
    let config = config::HostConfig::load_or_init(custom_path).await;

    // Initialize the global sandboxing flag
    let _ = crate::capabilities::fs::SANDBOX_HOME.set(config.sandbox_home);

    match cli.command {
        Some(Commands::Config) => {
            config::tui::run_tui(config).await?;
            Ok(())
        }
        Some(Commands::Pair) => {
            println!("=== NEURAL LINK PAIRING ===");
            println!("\nHost ID: {}", config.host_id);
            println!("Display Name: {}", config.host_name);

            use qr2term::print_qr;
            println!("\nScan this code from the Frankn App:");
            let qr_payload = format!("{}|{}", config.host_id, config.host_name);
            print_qr(&qr_payload).expect("Failed to print QR code");
            println!("\nKeep this ID secure.\n");
            Ok(())
        }
        Some(Commands::DoheeWorker { model }) => {
            crate::capabilities::inference::engine::run_dohee_worker(&model).await;
            Ok(())
        }
        Some(Commands::ProbeCamera) => {
            println!("=== FRANKN CAMERA PROBE ===");
            let cameras = capabilities::camera::probe_cameras().await;
            if cameras.is_empty() {
                println!("No /dev/video* devices found.");
            } else {
                for cam in &cameras {
                    println!("\nDevice Path : {}", cam.device_path);
                    println!("  Name        : {}", cam.name);
                    println!("  Functional  : {}", if cam.is_functional { "YES" } else { "NO" });
                    println!("  Type        : {}", if cam.is_dummy { "Virtual/Loopback" } else { "Physical Hardware" });
                    println!("  Formats     : {}", if cam.formats.is_empty() { "None/Unknown".into() } else { cam.formats.join(", ") });
                    println!("  Resolutions : {}", if cam.resolutions.is_empty() { "None/Unknown".into() } else { cam.resolutions.join(", ") });
                }

                if let Some(best) = capabilities::camera::get_best_camera_device().await {
                    println!("\n>>> Primary selected capture camera: {}\n", best);
                }
            }
            Ok(())
        }
        None => {
            match config.mode {
                config::RuntimeMode::Host => {
                    let runtime = app::HostRuntime::new(config);
                    runtime.run().await
                }
                config::RuntimeMode::Node => {
                    let runtime = app::NodeRuntime::new(config);
                    runtime.run().await
                }
            }
        }
    }
}
