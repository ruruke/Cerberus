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
