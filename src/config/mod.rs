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

    /// Docker networks configuration
    #[serde(default)]
    pub networks: std::collections::HashMap<String, NetworkConfig>,

    /// Docker volumes configuration
    #[serde(default)]
    pub volumes: std::collections::HashMap<String, VolumeConfig>,

    /// Docker secrets configuration
    #[serde(default)]
    pub secrets: std::collections::HashMap<String, SecretConfig>,

    /// Docker configs configuration
    #[serde(default)]
    pub configs: std::collections::HashMap<String, ConfigFileConfig>,

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

/// Docker build configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct DockerBuildConfig {
    /// Build context path
    pub context: String,
    
    /// Dockerfile path
    #[serde(default)]
    pub dockerfile: Option<String>,
    
    /// Build args
    #[serde(default)]
    pub args: std::collections::HashMap<String, String>,
    
    /// Build target stage
    #[serde(default)]
    pub target: Option<String>,
    
    /// Additional contexts
    #[serde(default)]
    pub additional_contexts: std::collections::HashMap<String, String>,
}

/// Docker service dependencies
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum DependsOn {
    /// Simple list of service names
    Simple(Vec<String>),
    /// Detailed dependencies with conditions
    Detailed(std::collections::HashMap<String, DependencyCondition>),
}

/// Dependency condition
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DependencyCondition {
    /// Condition type
    pub condition: String,
    /// Optional restart flag
    #[serde(default)]
    pub restart: Option<bool>,
}

/// Healthcheck configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct HealthcheckConfig {
    /// Test command
    pub test: Vec<String>,
    
    /// Check interval
    #[serde(default = "default_healthcheck_interval")]
    pub interval: String,
    
    /// Timeout
    #[serde(default = "default_healthcheck_timeout")]
    pub timeout: String,
    
    /// Retries
    #[serde(default = "default_healthcheck_retries")]
    pub retries: u32,
    
    /// Start period
    #[serde(default)]
    pub start_period: Option<String>,
    
    /// Start interval
    #[serde(default)]
    pub start_interval: Option<String>,
}

fn default_healthcheck_interval() -> String {
    "30s".to_string()
}

fn default_healthcheck_timeout() -> String {
    "10s".to_string()
}

fn default_healthcheck_retries() -> u32 {
    3
}

/// Logging configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct LoggingDriverConfig {
    /// Driver type
    pub driver: String,
    
    /// Driver options
    #[serde(default)]
    pub options: std::collections::HashMap<String, String>,
}

/// Resource limits
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct ResourcesConfig {
    /// Resource limits
    #[serde(default)]
    pub limits: Option<ResourceLimits>,
    
    /// Resource reservations
    #[serde(default)]
    pub reservations: Option<ResourceLimits>,
}

/// Resource limits specification
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct ResourceLimits {
    /// CPU limit
    #[serde(default)]
    pub cpus: Option<String>,
    
    /// Memory limit
    #[serde(default)]
    pub memory: Option<String>,
    
    /// PID limit
    #[serde(default)]
    pub pids: Option<u32>,
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

    /// Docker image for Anubis
    #[serde(default = "default_anubis_image")]
    pub image: String,

    /// Serve robots.txt flag
    #[serde(default = "default_serve_robots_txt")]
    pub serve_robots_txt: String,

    /// Policy filename path
    #[serde(default = "default_policy_fname")]
    pub policy_fname: String,

    /// Docker volumes
    #[serde(default)]
    pub volumes: Vec<String>,

    /// Docker networks
    #[serde(default)]
    pub networks: Vec<String>,

    /// Docker restart policy
    #[serde(default = "default_anubis_restart")]
    pub restart: String,
}

impl Default for AnubisConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            bind: default_anubis_bind(),
            target: default_anubis_target(),
            difficulty: default_anubis_difficulty(),
            metrics_bind: default_anubis_metrics_bind(),
            image: default_anubis_image(),
            serve_robots_txt: default_serve_robots_txt(),
            policy_fname: default_policy_fname(),
            volumes: Vec::new(),
            networks: Vec::new(),
            restart: default_anubis_restart(),
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

fn default_anubis_image() -> String {
    "ghcr.io/techarohq/anubis:latest".to_string()
}

fn default_serve_robots_txt() -> String {
    "true".to_string()
}

fn default_policy_fname() -> String {
    "/data/cfg/botPolicy.json".to_string()
}

fn default_anubis_restart() -> String {
    "always".to_string()
}

/// Docker network configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct NetworkConfig {
    /// Network driver
    #[serde(default = "default_network_driver")]
    pub driver: String,

    /// Driver options
    #[serde(default)]
    pub driver_opts: std::collections::HashMap<String, String>,

    /// IPAM configuration
    #[serde(default)]
    pub ipam: Option<IpamConfig>,

    /// External network flag
    #[serde(default)]
    pub external: bool,

    /// External network name
    #[serde(default)]
    pub name: Option<String>,

    /// Enable IPv6
    #[serde(default)]
    pub enable_ipv6: bool,

    /// Labels
    #[serde(default)]
    pub labels: std::collections::HashMap<String, String>,
}

fn default_network_driver() -> String {
    "bridge".to_string()
}

/// IPAM (IP Address Management) configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct IpamConfig {
    /// IPAM driver
    #[serde(default)]
    pub driver: Option<String>,

    /// Driver options
    #[serde(default)]
    pub driver_opts: std::collections::HashMap<String, String>,

    /// Network configuration
    #[serde(default)]
    pub config: Vec<IpamNetworkConfig>,
}

/// IPAM network configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct IpamNetworkConfig {
    /// Subnet
    #[serde(default)]
    pub subnet: Option<String>,

    /// IP range
    #[serde(default)]
    pub ip_range: Option<String>,

    /// Gateway
    #[serde(default)]
    pub gateway: Option<String>,

    /// Auxiliary addresses
    #[serde(default)]
    pub aux_addresses: std::collections::HashMap<String, String>,
}

/// Docker volume configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct VolumeConfig {
    /// Volume driver
    #[serde(default)]
    pub driver: Option<String>,

    /// Driver options
    #[serde(default)]
    pub driver_opts: std::collections::HashMap<String, String>,

    /// External volume flag
    #[serde(default)]
    pub external: bool,

    /// External volume name
    #[serde(default)]
    pub name: Option<String>,

    /// Labels
    #[serde(default)]
    pub labels: std::collections::HashMap<String, String>,
}

/// Docker secret configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum SecretConfig {
    /// Simple file-based secret
    File {
        /// File path
        file: String,
    },
    /// Environment variable secret
    Environment {
        /// Environment variable name
        environment: String,
    },
    /// External secret reference
    External {
        /// External flag
        external: bool,
        /// External secret name
        #[serde(default)]
        name: Option<String>,
    },
    /// Inline content secret
    Content {
        /// Content string
        content: String,
    },
}

/// Docker config file configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum ConfigFileConfig {
    /// Simple file-based config
    File {
        /// File path
        file: String,
    },
    /// Environment variable config
    Environment {
        /// Environment variable name
        environment: String,
    },
    /// External config reference
    External {
        /// External flag
        external: bool,
        /// External config name
        #[serde(default)]
        name: Option<String>,
    },
    /// Inline content config
    Content {
        /// Content string
        content: String,
    },
}

/// Service secret reference
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum ServiceSecretRef {
    /// Simple secret name
    Simple(String),
    /// Detailed secret configuration
    Detailed {
        /// Secret name
        source: String,
        /// Target path in container
        #[serde(default)]
        target: Option<String>,
        /// File mode (octal)
        #[serde(default)]
        mode: Option<u32>,
        /// User ID
        #[serde(default)]
        uid: Option<String>,
        /// Group ID
        #[serde(default)]
        gid: Option<String>,
    },
}

/// Service config reference
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(untagged)]
pub enum ServiceConfigRef {
    /// Simple config name
    Simple(String),
    /// Detailed config configuration
    Detailed {
        /// Config name
        source: String,
        /// Target path in container
        #[serde(default)]
        target: Option<String>,
        /// File mode (octal)
        #[serde(default)]
        mode: Option<u32>,
        /// User ID
        #[serde(default)]
        uid: Option<String>,
        /// Group ID
        #[serde(default)]
        gid: Option<String>,
    },
}

/// Docker deploy configuration for Swarm mode
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct DeployConfig {
    /// Deployment mode
    #[serde(default)]
    pub mode: Option<String>,

    /// Number of replicas
    #[serde(default)]
    pub replicas: Option<u32>,

    /// Resource constraints
    #[serde(default)]
    pub resources: Option<ResourcesConfig>,

    /// Update configuration
    #[serde(default)]
    pub update_config: Option<UpdateConfig>,

    /// Rollback configuration
    #[serde(default)]
    pub rollback_config: Option<RollbackConfig>,

    /// Restart policy
    #[serde(default)]
    pub restart_policy: Option<RestartPolicyConfig>,

    /// Placement constraints
    #[serde(default)]
    pub placement: Option<PlacementConfig>,

    /// Labels
    #[serde(default)]
    pub labels: std::collections::HashMap<String, String>,
}

/// Update configuration for deployments
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct UpdateConfig {
    /// Parallelism level
    #[serde(default)]
    pub parallelism: Option<u32>,

    /// Update delay
    #[serde(default)]
    pub delay: Option<String>,

    /// Failure action
    #[serde(default)]
    pub failure_action: Option<String>,

    /// Monitor duration
    #[serde(default)]
    pub monitor: Option<String>,

    /// Max failure ratio
    #[serde(default)]
    pub max_failure_ratio: Option<f64>,

    /// Update order
    #[serde(default)]
    pub order: Option<String>,
}

/// Rollback configuration for deployments
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct RollbackConfig {
    /// Parallelism level
    #[serde(default)]
    pub parallelism: Option<u32>,

    /// Rollback delay
    #[serde(default)]
    pub delay: Option<String>,

    /// Failure action
    #[serde(default)]
    pub failure_action: Option<String>,

    /// Monitor duration
    #[serde(default)]
    pub monitor: Option<String>,

    /// Max failure ratio
    #[serde(default)]
    pub max_failure_ratio: Option<f64>,

    /// Rollback order
    #[serde(default)]
    pub order: Option<String>,
}

/// Restart policy configuration
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct RestartPolicyConfig {
    /// Restart condition
    #[serde(default)]
    pub condition: Option<String>,

    /// Restart delay
    #[serde(default)]
    pub delay: Option<String>,

    /// Max attempts
    #[serde(default)]
    pub max_attempts: Option<u32>,

    /// Restart window
    #[serde(default)]
    pub window: Option<String>,
}

/// Placement configuration for services
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Default)]
pub struct PlacementConfig {
    /// Placement constraints
    #[serde(default)]
    pub constraints: Vec<String>,

    /// Placement preferences
    #[serde(default)]
    pub preferences: Vec<PlacementPreference>,

    /// Max replicas per node
    #[serde(default)]
    pub max_replicas_per_node: Option<u32>,
}

/// Placement preference
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PlacementPreference {
    /// Spread configuration
    pub spread: String,
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

impl ProxyType {
    /// Convert to string representation
    pub fn as_str(&self) -> &'static str {
        match self {
            ProxyType::Caddy => "caddy",
            ProxyType::Nginx => "nginx", 
            ProxyType::HaProxy => "haproxy",
            ProxyType::Traefik => "traefik",
        }
    }
}

impl std::fmt::Display for ProxyType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
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

    /// Docker build context path
    #[serde(default)]
    pub build_context: Option<String>,

    /// Docker build dockerfile path
    #[serde(default)]
    pub build_dockerfile: Option<String>,

    /// Docker entrypoint command
    #[serde(default)]
    pub entrypoint: Option<String>,

    /// Docker volumes
    #[serde(default)]
    pub volumes: Vec<String>,

    /// Docker networks
    #[serde(default)]
    pub networks: Vec<String>,

    /// Docker restart policy
    #[serde(default)]
    pub restart: Option<String>,

    /// Docker secrets references
    #[serde(default)]
    pub secrets: Vec<ServiceSecretRef>,

    /// Docker configs references
    #[serde(default)]
    pub configs: Vec<ServiceConfigRef>,

    /// Docker service dependencies
    #[serde(default)]
    pub depends_on: Option<DependsOn>,

    /// Docker healthcheck configuration
    #[serde(default)]
    pub healthcheck: Option<HealthcheckConfig>,

    /// Docker logging configuration
    #[serde(default)]
    pub logging: Option<LoggingDriverConfig>,

    /// Docker resource constraints
    #[serde(default)]
    pub deploy: Option<DeployConfig>,

    /// Environment variables
    #[serde(default)]
    pub environment: std::collections::HashMap<String, String>,

    /// Environment files
    #[serde(default)]
    pub env_file: Vec<String>,

    /// Exposed ports (internal only)
    #[serde(default)]
    pub expose: Vec<String>,

    /// External links (deprecated but supported)
    #[serde(default)]
    pub external_links: Vec<String>,

    /// Labels
    #[serde(default)]
    pub labels: std::collections::HashMap<String, String>,
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
