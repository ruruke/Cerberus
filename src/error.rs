//! # Error handling for Cerberus
//!
//! This module defines the error types used throughout the Cerberus application.
//! It uses `thiserror` for ergonomic error handling and `anyhow` for error context.

use std::path::PathBuf;

/// Main error type for Cerberus operations
#[derive(thiserror::Error, Debug)]
pub enum CerberusError {
    /// Configuration file errors
    #[error("Configuration error: {message}")]
    Config { message: String },

    /// TOML parsing errors
    #[error("TOML parsing error in {file}: {source}")]
    TomlParse {
        file: PathBuf,
        #[source]
        source: toml::de::Error,
    },

    /// File I/O errors
    #[error("File I/O error for {file}: {source}")]
    Io {
        file: PathBuf,
        #[source]
        source: std::io::Error,
    },

    /// Template rendering errors
    #[error("Template rendering error for {template}: {source}")]
    TemplateRender {
        template: String,
        #[source]
        source: handlebars::RenderError,
    },

    /// Template registration errors
    #[error("Template registration error: {source}")]
    TemplateRegister {
        #[source]
        source: handlebars::TemplateError,
    },

    /// Docker Compose validation errors
    #[error("Docker Compose validation failed: {message}")]
    DockerComposeValidation { message: String },

    /// Proxy configuration errors
    #[error("Proxy configuration error for {proxy}: {message}")]
    ProxyConfig { proxy: String, message: String },

    /// Scaling configuration errors
    #[error("Scaling configuration error: {message}")]
    Scaling { message: String },

    /// General validation errors
    #[error("Validation error: {message}")]
    Validation { message: String },
}

/// Result type alias for Cerberus operations
pub type Result<T> = std::result::Result<T, CerberusError>;

impl CerberusError {
    /// Create a new configuration error
    pub fn config(message: impl Into<String>) -> Self {
        Self::Config {
            message: message.into(),
        }
    }

    /// Create a new TOML parsing error
    pub fn toml_parse(file: impl Into<PathBuf>, source: toml::de::Error) -> Self {
        Self::TomlParse {
            file: file.into(),
            source,
        }
    }

    /// Create a new I/O error
    pub fn io(file: impl Into<PathBuf>, source: std::io::Error) -> Self {
        Self::Io {
            file: file.into(),
            source,
        }
    }

    /// Create a new template rendering error
    pub fn template_render(template: impl Into<String>, source: handlebars::RenderError) -> Self {
        Self::TemplateRender {
            template: template.into(),
            source,
        }
    }

    /// Create a new proxy configuration error
    pub fn proxy_config(proxy: impl Into<String>, message: impl Into<String>) -> Self {
        Self::ProxyConfig {
            proxy: proxy.into(),
            message: message.into(),
        }
    }

    /// Create a new validation error
    pub fn validation(message: impl Into<String>) -> Self {
        Self::Validation {
            message: message.into(),
        }
    }
}

impl From<std::io::Error> for CerberusError {
    fn from(err: std::io::Error) -> Self {
        Self::Io {
            file: PathBuf::from("unknown"),
            source: err,
        }
    }
}

impl From<handlebars::RenderError> for CerberusError {
    fn from(err: handlebars::RenderError) -> Self {
        Self::TemplateRender {
            template: "unknown".to_string(),
            source: err,
        }
    }
}

impl From<handlebars::TemplateError> for CerberusError {
    fn from(err: handlebars::TemplateError) -> Self {
        Self::TemplateRegister { source: err }
    }
}

impl From<serde_yaml::Error> for CerberusError {
    fn from(err: serde_yaml::Error) -> Self {
        Self::config(format!("YAML error: {}", err))
    }
}

impl From<serde_json::Error> for CerberusError {
    fn from(err: serde_json::Error) -> Self {
        Self::config(format!("JSON error: {}", err))
    }
}
