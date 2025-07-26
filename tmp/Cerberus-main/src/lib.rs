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
        // Create output directory if it doesn't exist
        tokio::fs::create_dir_all(&self.output_dir).await?;

        // Generate Docker Compose configuration
        self.generate_docker_compose().await?;

        // Generate proxy configurations
        self.generate_proxy_configs().await?;

        // Generate Dockerfiles
        self.generate_dockerfiles().await?;

        // Generate Anubis configuration if enabled
        if self.config.anubis.enabled {
            self.generate_anubis_config().await?;
        }

        Ok(())
    }

    /// Generate Docker Compose configuration
    async fn generate_docker_compose(&self) -> Result<()> {
        let generator = generators::DockerComposeGenerator::new(&self.config);
        let compose_content = generator.generate()?;

        let output_path = self.output_dir.join("docker-compose.yaml");
        tokio::fs::write(output_path, compose_content).await?;

        Ok(())
    }

    /// Generate proxy configurations for all proxy layers
    async fn generate_proxy_configs(&self) -> Result<()> {
        let generator = generators::ProxyConfigGenerator::new(&self.config);

        for proxy in &self.config.proxies {
            let config_content = generator.generate_for_proxy(proxy)?;

            let proxy_dir = self.output_dir.join("proxy-configs").join(&proxy.name);
            tokio::fs::create_dir_all(&proxy_dir).await?;

            let config_file = match proxy.proxy_type {
                config::ProxyType::Caddy => "Caddyfile",
                config::ProxyType::Nginx => "nginx.conf",
                config::ProxyType::HaProxy => "haproxy.cfg",
                config::ProxyType::Traefik => "traefik.yml",
            };

            let output_path = proxy_dir.join(config_file);
            tokio::fs::write(output_path, config_content).await?;
        }

        Ok(())
    }

    /// Generate Dockerfiles for all services
    async fn generate_dockerfiles(&self) -> Result<()> {
        let generator = generators::DockerfileGenerator::new(&self.config);

        for proxy in &self.config.proxies {
            let dockerfile_content = generator.generate_for_proxy(proxy)?;

            let dockerfile_dir = self.output_dir.join("dockerfiles").join(&proxy.name);
            tokio::fs::create_dir_all(&dockerfile_dir).await?;

            let output_path = dockerfile_dir.join("Dockerfile");
            tokio::fs::write(output_path, dockerfile_content).await?;
        }

        Ok(())
    }

    /// Generate Anubis DDoS protection configuration
    async fn generate_anubis_config(&self) -> Result<()> {
        let generator = generators::AnubisGenerator::new(&self.config);
        let anubis_content = generator.generate()?;

        let anubis_dir = self.output_dir.join("anubis");
        tokio::fs::create_dir_all(&anubis_dir).await?;

        let output_path = anubis_dir.join("botPolicy.json");
        tokio::fs::write(output_path, anubis_content).await?;

        Ok(())
    }

    /// Validate generated configurations
    ///
    /// Performs syntax validation on generated Docker Compose and other files
    ///
    /// # Errors
    /// Returns error if any validation fails
    pub async fn validate(&self) -> Result<()> {
        // Validate Docker Compose syntax
        let compose_path = self.output_dir.join("docker-compose.yaml");
        if compose_path.exists() {
            generators::DockerComposeGenerator::validate_file(&compose_path).await?;
        }

        Ok(())
    }
}
