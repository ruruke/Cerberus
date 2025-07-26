//! # Configuration generators for Cerberus
//!
//! This module contains generators for various configuration files including
//! Docker Compose, proxy configurations, Dockerfiles, and Anubis settings.

use crate::{config::Config, Result};

pub mod docker_compose;
pub mod proxy_config;
pub mod dockerfile;
pub mod anubis;

pub use docker_compose::DockerComposeGenerator;
pub use proxy_config::ProxyConfigGenerator;
pub use dockerfile::DockerfileGenerator;
pub use anubis::AnubisGenerator;