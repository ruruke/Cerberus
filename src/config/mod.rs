//! # Configuration management for Cerberus
//!
//! This module handles loading, parsing, and validating TOML configuration files.
//! It provides type-safe access to all configuration options with sensible defaults.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

use crate::{CerberusError, Result};

/// Main configuration structure
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Config {
    /// Project-level configuration
    pub project: ProjectConfig,

    /// Global settings
    #[serde(default)]
    pub global: GlobalConfig,

    /// TLS/SSL configuration
    #[serde(default)]
    pub tls: TlsConfig,

    /// Anubis DDoS protection configuration
    #[serde(default)]
    pub anubis: AnubisConfig,

    /// Proxy layer configurations
    #[serde(default)]
    pub proxies: Vec<ProxyConfig>,

    /// Backend service configurations
    #[serde(default)]
    pub services: Vec<ServiceConfig>,

    /// Logging configuration
    #[serde(default)]
    pub logging: LoggingConfig,
}

/// Project-level configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProjectConfig {
    /// Project name
    pub name: String,

    /// Enable auto-scaling
    #[serde(default)]
    pub scaling: bool,
}

/// Global Caddy/proxy settings
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct GlobalConfig {
    /// Automatic HTTPS setting
    #[serde(default = "default_auto_https")]
    pub auto_https: String,

    /// Admin API setting
    #[serde(default = "default_admin")]
    pub admin: String,
}

impl Default for GlobalConfig {
    fn default() -> Self {
        Self {
            auto_https: default_auto_https(),
            admin: default_admin(),
        }
    }
}

fn default_auto_https() -> String {
    "off".to_string()
}

fn default_admin() -> String {
    "off".to_string()
}

/// TLS/SSL configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct TlsConfig {
    /// Enable TLS
    #[serde(default)]
    pub enabled: bool,

    /// CA configuration
    #[serde(default)]
    pub ca: Option<CaConfig>,

    /// Certificate configurations
    #[serde(default)]
    pub certificates: Vec<CertificateConfig>,
}

/// Certificate Authority configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CaConfig {
    /// Enable internal CA
    #[serde(default)]
    pub enabled: bool,

    /// Root certificate path
    pub root_cert: Option<String>,

    /// Root key path
    pub root_key: Option<String>,
}

/// Individual certificate configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CertificateConfig {
    /// Domain pattern (e.g., "*.example.com")
    pub domain: String,

    /// Certificate file path
    pub cert_file: String,

    /// Private key file path
    pub key_file: String,
}

/// Anubis DDoS protection configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AnubisConfig {
    /// Enable Anubis DDoS protection
    #[serde(default)]
    pub enabled: bool,

    /// Bind address for Anubis
    #[serde(default = "default_anubis_bind")]
    pub bind: String,

    /// Target upstream for protected traffic
    #[serde(default = "default_anubis_target")]
    pub target: String,

    /// Challenge difficulty level (1-10)
    #[serde(default = "default_anubis_difficulty")]
    pub difficulty: u8,

    /// Metrics endpoint bind address
    #[serde(default = "default_anubis_metrics_bind")]
    pub metrics_bind: String,
}

impl Default for AnubisConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            bind: default_anubis_bind(),
            target: default_anubis_target(),
            difficulty: default_anubis_difficulty(),
            metrics_bind: default_anubis_metrics_bind(),
        }
    }
}

fn default_anubis_bind() -> String {
    ":8080".to_string()
}

fn default_anubis_target() -> String {
    "http://proxy-2:80".to_string()
}

fn default_anubis_difficulty() -> u8 {
    5
}

fn default_anubis_metrics_bind() -> String {
    ":9090".to_string()
}

/// Proxy type enumeration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ProxyType {
    Caddy,
    Nginx,
    #[serde(rename = "haproxy")]
    HaProxy,
    Traefik,
}

/// Route type for conditional routing
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum RouteType {
    /// Direct routing (bypass DDoS protection)
    Direct,
    /// Conditional routing (some paths bypass DDoS protection)
    Conditional,
}

/// Routing configuration for proxy layers
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RouteConfig {
    /// Type of routing
    #[serde(rename = "type")]
    pub route_type: RouteType,

    /// Domain this route applies to
    pub domain: String,

    /// Upstream destination
    pub upstream: String,

    /// Paths that bypass DDoS protection (for conditional routing)
    #[serde(default)]
    pub bypass_paths: Vec<String>,
}

/// Proxy layer configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProxyConfig {
    /// Proxy instance name
    pub name: String,

    /// Proxy software type
    #[serde(rename = "type")]
    pub proxy_type: ProxyType,

    /// External port exposed to internet
    pub external_port: u16,

    /// Internal container port
    #[serde(default = "default_internal_port")]
    pub internal_port: u16,

    /// Proxy layer number
    #[serde(default)]
    pub layer: Option<u8>,

    /// Number of instances for scaling
    #[serde(default = "default_instances")]
    pub instances: u8,

    /// Load balancing algorithm
    #[serde(default)]
    pub algorithm: Option<String>,

    /// Maximum connections
    #[serde(default)]
    pub max_connections: Option<u32>,

    /// Default upstream for unmatched requests
    #[serde(default)]
    pub default_upstream: Option<String>,

    /// Specific routing configurations
    #[serde(default)]
    pub routes: Vec<RouteConfig>,
}

fn default_internal_port() -> u16 {
    80
}

fn default_instances() -> u8 {
    1
}

/// Backend service configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServiceConfig {
    /// Service name
    pub name: String,

    /// Domain this service serves
    pub domain: String,

    /// Upstream URL
    pub upstream: String,

    /// Enable WebSocket support
    #[serde(default)]
    pub websocket: bool,

    /// Enable compression
    #[serde(default = "default_compression")]
    pub compress: bool,

    /// Maximum request body size
    #[serde(default = "default_max_body_size")]
    pub max_body_size: String,

    /// Custom request headers
    #[serde(flatten)]
    pub headers: HashMap<String, String>,
}

fn default_compression() -> bool {
    true
}

fn default_max_body_size() -> String {
    "1m".to_string()
}

/// Logging configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LoggingConfig {
    /// Log level
    #[serde(default = "default_log_level")]
    pub level: String,

    /// Log format
    #[serde(default = "default_log_format")]
    pub format: String,

    /// Log output destination
    #[serde(default = "default_log_output")]
    pub output: String,
}

impl Default for LoggingConfig {
    fn default() -> Self {
        Self {
            level: default_log_level(),
            format: default_log_format(),
            output: default_log_output(),
        }
    }
}

fn default_log_level() -> String {
    "INFO".to_string()
}

fn default_log_format() -> String {
    "json".to_string()
}

fn default_log_output() -> String {
    "/var/log/cerberus.log".to_string()
}

impl Config {
    /// Load configuration from a TOML file
    ///
    /// # Arguments
    /// * `path` - Path to the TOML configuration file
    ///
    /// # Errors
    /// Returns error if file cannot be read or parsed
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path).map_err(|e| CerberusError::io(path, e))?;

        let config: Config =
            toml::from_str(&content).map_err(|e| CerberusError::toml_parse(path, e))?;

        config.validate()?;

        Ok(config)
    }

    /// Validate the configuration
    ///
    /// Performs semantic validation beyond what's possible with serde
    ///
    /// # Errors
    /// Returns error if configuration is invalid
    pub fn validate(&self) -> Result<()> {
        // Validate project name is not empty
        if self.project.name.trim().is_empty() {
            return Err(CerberusError::validation("Project name cannot be empty"));
        }

        // Validate proxy configurations
        for (index, proxy) in self.proxies.iter().enumerate() {
            if proxy.name.trim().is_empty() {
                return Err(CerberusError::validation(format!(
                    "Proxy {index} name cannot be empty"
                )));
            }

            if proxy.external_port == 0 {
                return Err(CerberusError::validation(format!(
                    "Proxy {} external_port must be greater than 0",
                    proxy.name
                )));
            }

            if proxy.instances == 0 {
                return Err(CerberusError::validation(format!(
                    "Proxy {} instances must be greater than 0",
                    proxy.name
                )));
            }
        }

        // Validate service configurations
        for (index, service) in self.services.iter().enumerate() {
            if service.name.trim().is_empty() {
                return Err(CerberusError::validation(format!(
                    "Service {index} name cannot be empty"
                )));
            }

            if service.domain.trim().is_empty() {
                return Err(CerberusError::validation(format!(
                    "Service {} domain cannot be empty",
                    service.name
                )));
            }

            if service.upstream.trim().is_empty() {
                return Err(CerberusError::validation(format!(
                    "Service {} upstream cannot be empty",
                    service.name
                )));
            }
        }

        // Validate Anubis configuration
        if self.anubis.enabled && self.anubis.difficulty > 10 {
            return Err(CerberusError::validation(
                "Anubis difficulty must be between 1 and 10",
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests;
