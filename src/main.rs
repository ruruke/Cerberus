//! # Cerberus CLI
//!
//! Command-line interface for the Cerberus multi-layer proxy architecture system.

use clap::{Arg, Command};
use std::path::PathBuf;
use tracing::{info, error};
use tracing_subscriber;

use cerberus::{Cerberus, Result};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let matches = Command::new("cerberus")
        .version("0.1.0")
        .about("Multi-layer proxy architecture system")
        .arg(
            Arg::new("config")
                .short('c')
                .long("config")
                .value_name("FILE")
                .help("Configuration file path")
                .default_value("config.toml")
        )
        .arg(
            Arg::new("output")
                .short('o')
                .long("output")
                .value_name("DIR")
                .help("Output directory for generated files")
                .default_value("built")
        )
        .subcommand(
            Command::new("generate")
                .about("Generate all configuration files")
                .arg(
                    Arg::new("force")
                        .long("force")
                        .help("Overwrite existing files")
                        .action(clap::ArgAction::SetTrue)
                )
        )
        .subcommand(
            Command::new("validate")
                .about("Validate configuration and generated files")
        )
        .subcommand(
            Command::new("clean")
                .about("Clean output directory")
        )
        .get_matches();

    let config_path = PathBuf::from(matches.get_one::<String>("config").unwrap());
    let output_dir = PathBuf::from(matches.get_one::<String>("output").unwrap());

    let cerberus = Cerberus::new(&config_path, &output_dir)?;

    match matches.subcommand() {
        Some(("generate", _sub_matches)) => {
            info!("Generating configuration files...");
            cerberus.generate_all().await?;
            info!("Configuration generation completed successfully");
        }
        Some(("validate", _sub_matches)) => {
            info!("Validating configuration...");
            cerberus.validate().await?;
            info!("Configuration validation completed successfully");
        }
        Some(("clean", _sub_matches)) => {
            info!("Cleaning output directory...");
            if output_dir.exists() {
                tokio::fs::remove_dir_all(&output_dir).await?;
                info!("Output directory cleaned");
            } else {
                info!("Output directory does not exist");
            }
        }
        _ => {
            error!("No subcommand provided. Use --help for usage information.");
            std::process::exit(1);
        }
    }

    Ok(())
}