//! # Cerberus - Multi-Layer Proxy Architecture System
//!
//! Cerberus is a dynamic configuration-driven multi-layer proxy architecture system
//! that generates Docker configurations from TOML settings. It provides DDoS protection,
//! load balancing, auto-scaling, and flexible proxy management.
//!
//! ## Architecture
//!
//! ```text
//! Internet → HAProxy/Proxy → Anubis (DDoS) → Proxy-2 → Backend Services
//! ```
//!
//! ## Key Features
//!
//! - **Dynamic Configuration**: TOML-driven setup generation
//! - **Multiple Proxy Support**: Caddy, HAProxy, Nginx, Traefik
//! - **Auto-Scaling**: CPU/Memory/Connection-based scaling
//! - **DDoS Protection**: Anubis AI Firewall integration
//! - **Template System**: Pre-configured setups for common use cases

pub mod cli;
pub mod config;
pub mod error;
pub mod generators;
pub mod scaling;
pub mod templates;

pub use error::{CerberusError, Result};

/// The main Cerberus application struct
///
/// This struct manages the overall application state and coordinates
/// between different modules.
#[derive(Debug)]
pub struct Cerberus {
    /// Configuration loaded from TOML file
    config: config::Config,
    /// Output directory for generated files
    output_dir: std::path::PathBuf,
}

impl Cerberus {
    /// Create a new Cerberus instance
    ///
    /// # Arguments
    /// * `config_path` - Path to the TOML configuration file
    /// * `output_dir` - Directory where generated files will be written
    ///
    /// # Errors
    /// Returns error if config file cannot be read or parsed
    pub fn new(config_path: &std::path::Path, output_dir: &std::path::Path) -> Result<Self> {
        let config = config::Config::load(config_path)?;

        Ok(Self {
            config,
            output_dir: output_dir.to_path_buf(),
        })
    }

    /// Generate all configuration files
    ///
    /// This is the main entry point that orchestrates the generation
    /// of Docker Compose, Dockerfiles, proxy configs, and other files.
    ///
    /// # Errors
    /// Returns error if any generation step fails
    pub async fn generate_all(&self) -> Result<()> {
        let generator = generators::CerberusGenerator::new(
            &self.config,
            self.output_dir.to_string_lossy().to_string()
        );
        
        generator.generate_all().await?;
        Ok(())
    }

    /// Validate generated configurations
    ///
    /// Performs syntax validation on generated Docker Compose and other files
    ///
    /// # Errors
    /// Returns error if any validation fails
    pub async fn validate(&self) -> Result<()> {
        let generator = generators::CerberusGenerator::new(
            &self.config,
            self.output_dir.to_string_lossy().to_string()
        );
        
        generator.validate_generated().await?;
        Ok(())
    }

    /// Clean generated files
    ///
    /// Removes all generated configuration files and directories
    ///
    /// # Errors
    /// Returns error if cleanup fails
    pub async fn clean(&self) -> Result<()> {
        let generator = generators::CerberusGenerator::new(
            &self.config,
            self.output_dir.to_string_lossy().to_string()
        );
        
        generator.clean().await?;
        Ok(())
    }

    /// Get the loaded configuration
    pub fn config(&self) -> &config::Config {
        &self.config
    }

    /// Get the output directory
    pub fn output_dir(&self) -> &std::path::Path {
        &self.output_dir
    }
}
