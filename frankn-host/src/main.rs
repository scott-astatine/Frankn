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
    /// Manage host configuration
    Config,
    /// Display pairing ID and QR code
    Pair,
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
        None => {
            let runtime = app::HostRuntime::new(config);
            runtime.run().await
        }
    }
}
