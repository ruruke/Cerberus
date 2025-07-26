//! # Configuration generators for Cerberus
//!
//! This module contains generators for various configuration files including
//! Docker Compose, proxy configurations, Dockerfiles, and Anubis settings.
//!
//! ## Available Generators
//!
//! - **DockerComposeGenerator**: Generates docker-compose.yaml files
//! - **ProxyConfigGenerator**: Generates proxy configuration files (Caddy, Nginx, etc.)
//! - **DockerfileGenerator**: Generates custom Dockerfiles
//! - **AnubisGenerator**: Generates Anubis DDoS protection policies

pub mod anubis;
pub mod docker_compose;
pub mod dockerfile;
pub mod proxy_config;

pub use anubis::AnubisGenerator;
pub use docker_compose::DockerComposeGenerator;
pub use dockerfile::DockerfileGenerator;
pub use proxy_config::ProxyConfigGenerator;

use crate::{Result, config::Config};
use std::path::Path;
use tokio::fs;

/// Master generator that orchestrates all sub-generators
pub struct CerberusGenerator<'a> {
    config: &'a Config,
    output_dir: String,
}

impl<'a> CerberusGenerator<'a> {
    /// Create a new master generator
    pub fn new(config: &'a Config, output_dir: impl Into<String>) -> Self {
        Self {
            config,
            output_dir: output_dir.into(),
        }
    }

    /// Generate all configurations asynchronously
    pub async fn generate_all(&self) -> Result<()> {
        // Clean and create output directories
        self.clean_directories().await?;
        self.create_directories().await?;
        
        // Generate Docker Compose
        self.generate_docker_compose().await?;
        
        // Generate proxy configurations
        self.generate_proxy_configs().await?;
        
        // Generate Dockerfiles
        self.generate_dockerfiles().await?;
        
        // Generate Anubis configuration if enabled
        if self.config.anubis.enabled {
            self.generate_anubis_config().await?;
        }
        
        tracing::info!("All configurations generated successfully");
        Ok(())
    }

    /// Clean output directories
    async fn clean_directories(&self) -> Result<()> {
        if Path::new(&self.output_dir).exists() {
            fs::remove_dir_all(&self.output_dir).await?;
            tracing::info!("Cleaned output directory: {}", self.output_dir);
        }
        Ok(())
    }

    /// Create necessary output directories
    async fn create_directories(&self) -> Result<()> {
        let dirs = [
            &self.output_dir,
            &format!("{}/proxy-configs", self.output_dir),
            &format!("{}/dockerfiles", self.output_dir),
            &format!("{}/anubis", self.output_dir),
            &format!("{}/logs", self.output_dir),
        ];

        for dir in dirs {
            if !Path::new(dir).exists() {
                fs::create_dir_all(dir).await?;
                tracing::debug!("Created directory: {}", dir);
            }
        }

        // Create subdirectories for each proxy
        for proxy in &self.config.proxies {
            let proxy_dir = format!("{}/proxy-configs/{}", self.output_dir, proxy.name);
            let dockerfile_dir = format!("{}/dockerfiles/{}", self.output_dir, proxy.name);
            
            fs::create_dir_all(&proxy_dir).await?;
            fs::create_dir_all(&dockerfile_dir).await?;
            tracing::debug!("Created proxy directories: {}, {}", proxy_dir, dockerfile_dir);
        }

        Ok(())
    }

    /// Generate Docker Compose configuration
    async fn generate_docker_compose(&self) -> Result<()> {
        let generator = DockerComposeGenerator::new(self.config);
        let yaml_content = generator.generate()?;
        
        let file_path = format!("{}/docker-compose.yaml", self.output_dir);
        fs::write(&file_path, yaml_content).await?;
        tracing::info!("Generated Docker Compose: {}", file_path);
        
        Ok(())
    }

    /// Generate proxy configurations
    async fn generate_proxy_configs(&self) -> Result<()> {
        let generator = ProxyConfigGenerator::new(self.config);
        
        for proxy in &self.config.proxies {
            let config_content = generator.generate_for_proxy(proxy)?;
            let config_file = ProxyConfigGenerator::get_file_extension(proxy.proxy_type.as_str());
            let file_path = format!("{}/proxy-configs/{}/{}", self.output_dir, proxy.name, config_file);
            
            fs::write(&file_path, config_content).await?;
            tracing::info!("Generated {} config: {}", proxy.proxy_type, file_path);
        }
        
        Ok(())
    }

    /// Generate Dockerfiles
    async fn generate_dockerfiles(&self) -> Result<()> {
        let generator = DockerfileGenerator::new(self.config);
        
        for proxy in &self.config.proxies {
            let dockerfile_content = generator.generate_for_proxy(proxy)?;
            let file_path = format!("{}/dockerfiles/{}/Dockerfile", self.output_dir, proxy.name);
            
            fs::write(&file_path, dockerfile_content).await?;
            tracing::info!("Generated Dockerfile: {}", file_path);
        }
        
        // Generate multi-stage Dockerfile
        let multi_stage_content = generator.generate_multi_stage()?;
        let multi_stage_path = format!("{}/Dockerfile.multi-stage", self.output_dir);
        fs::write(&multi_stage_path, multi_stage_content).await?;
        tracing::info!("Generated multi-stage Dockerfile: {}", multi_stage_path);
        
        Ok(())
    }

    /// Generate Anubis configuration
    async fn generate_anubis_config(&self) -> Result<()> {
        let generator = AnubisGenerator::new(self.config);
        
        // Generate bot policy
        let bot_policy = generator.generate()?;
        let policy_path = format!("{}/anubis/botPolicy.json", self.output_dir);
        fs::write(&policy_path, bot_policy).await?;
        tracing::info!("Generated Anubis bot policy: {}", policy_path);
        
        // Generate environment configuration
        let env_vars = generator.generate_env_config()?;
        let env_content = env_vars.join("\n");
        let env_path = format!("{}/anubis/.env", self.output_dir);
        fs::write(&env_path, env_content).await?;
        tracing::info!("Generated Anubis environment: {}", env_path);
        
        Ok(())
    }

    /// Validate all generated configurations
    pub async fn validate_generated(&self) -> Result<()> {
        tracing::info!("Validating generated configurations...");
        
        // Check Docker Compose syntax
        let compose_path = format!("{}/docker-compose.yaml", self.output_dir);
        if Path::new(&compose_path).exists() {
            // Try to parse the YAML to validate syntax
            let content = fs::read_to_string(&compose_path).await?;
            match serde_yaml::from_str::<serde_yaml::Value>(&content) {
                Ok(_) => tracing::info!("Docker Compose YAML is valid"),
                Err(e) => {
                    tracing::error!("Docker Compose YAML validation failed: {}", e);
                    return Err(crate::CerberusError::config(
                        format!("Invalid Docker Compose YAML: {}", e)
                    ));
                }
            }
        }
        
        // Check Anubis JSON syntax
        let anubis_path = format!("{}/anubis/botPolicy.json", self.output_dir);
        if Path::new(&anubis_path).exists() {
            let content = fs::read_to_string(&anubis_path).await?;
            match serde_json::from_str::<serde_json::Value>(&content) {
                Ok(_) => tracing::info!("Anubis bot policy JSON is valid"),
                Err(e) => {
                    tracing::error!("Anubis JSON validation failed: {}", e);
                    return Err(crate::CerberusError::config(
                        format!("Invalid Anubis JSON: {}", e)
                    ));
                }
            }
        }
        
        tracing::info!("All generated configurations validated successfully");
        Ok(())
    }

    /// Clean generated files
    pub async fn clean(&self) -> Result<()> {
        if Path::new(&self.output_dir).exists() {
            fs::remove_dir_all(&self.output_dir).await?;
            tracing::info!("Cleaned output directory: {}", self.output_dir);
        }
        Ok(())
    }
}
