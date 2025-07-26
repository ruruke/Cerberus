//! # Tests for configuration management
//!
//! These tests verify that TOML configuration loading, parsing, and validation
//! work correctly for all supported configuration patterns.

use super::*;
use pretty_assertions::assert_eq;
use std::io::Write;
use tempfile::NamedTempFile;

/// Helper function to create a temporary TOML file with given content
fn create_temp_config(content: &str) -> NamedTempFile {
    let mut file = NamedTempFile::new().expect("Failed to create temp file");
    file.write_all(content.as_bytes()).expect("Failed to write to temp file");
    file
}

#[test]
fn test_minimal_config_loading() {
    let content = r#"
[project]
name = "test-project"

[[proxies]]
name = "simple-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "web-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    assert_eq!(config.project.name, "test-project");
    assert!(!config.project.scaling);
    assert_eq!(config.proxies.len(), 1);
    assert_eq!(config.proxies[0].name, "simple-proxy");
    assert_eq!(config.proxies[0].proxy_type, ProxyType::Caddy);
    assert_eq!(config.proxies[0].external_port, 80);
    assert_eq!(config.services.len(), 1);
    assert_eq!(config.services[0].name, "web-service");
    assert_eq!(config.services[0].domain, "example.com");
}

#[test]
fn test_full_featured_config_loading() {
    let content = r#"
[project]
name = "full-featured-test"
scaling = true

[global]
auto_https = "on"
admin = "on"

[tls]
enabled = true

[[tls.certificates]]
domain = "*.example.com"
cert_file = "/etc/ssl/wildcard.crt"
key_file = "/etc/ssl/wildcard.key"

[anubis]
enabled = true
bind = ":8080"
target = "http://proxy-2:80"
difficulty = 7
metrics_bind = ":9090"

[[proxies]]
name = "proxy-layer1"
type = "caddy"
external_port = 80
layer = 1
instances = 2
default_upstream = "http://anubis:8080"

[[proxies.routes]]
type = "direct"
domain = "static.example.com"
upstream = "http://proxy-2:80"

[[proxies.routes]]
type = "conditional"
domain = "api.example.com"
upstream = "http://proxy-2:80"
bypass_paths = ["/health/*", "/metrics/*"]

[[proxies]]
name = "proxy-layer2"
type = "caddy"
external_port = 80
layer = 2
instances = 3

[[services]]
name = "main-app"
domain = "api.example.com"
upstream = "http://192.0.2.1:3000"
websocket = true
compress = true
max_body_size = "500m"

[[services]]
name = "static-files"
domain = "static.example.com"
upstream = "https://cdn.example.com/"
headers_response_cache_control = "public, max-age=86400"

[logging]
level = "INFO"
format = "json"
output = "/var/log/cerberus.log"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    // Test project config
    assert_eq!(config.project.name, "full-featured-test");
    assert!(config.project.scaling);

    // Test global config
    assert_eq!(config.global.auto_https, "on");
    assert_eq!(config.global.admin, "on");

    // Test TLS config
    assert!(config.tls.enabled);
    assert_eq!(config.tls.certificates.len(), 1);
    assert_eq!(config.tls.certificates[0].domain, "*.example.com");

    // Test Anubis config
    assert!(config.anubis.enabled);
    assert_eq!(config.anubis.difficulty, 7);

    // Test proxy configs
    assert_eq!(config.proxies.len(), 2);
    assert_eq!(config.proxies[0].instances, 2);
    assert_eq!(config.proxies[0].routes.len(), 2);
    assert_eq!(config.proxies[0].routes[0].route_type, RouteType::Direct);
    assert_eq!(config.proxies[0].routes[1].route_type, RouteType::Conditional);
    assert_eq!(config.proxies[0].routes[1].bypass_paths.len(), 2);

    // Test service configs
    assert_eq!(config.services.len(), 2);
    assert!(config.services[0].websocket);
    assert_eq!(config.services[0].max_body_size, "500m");
}

#[test]
fn test_anubis_disabled_config() {
    let content = r#"
[project]
name = "no-anubis-test"

[anubis]
enabled = false

[[proxies]]
name = "simple-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "web-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    assert!(!config.anubis.enabled);
    // Default values should still be set
    assert_eq!(config.anubis.bind, ":8080");
    assert_eq!(config.anubis.difficulty, 5);
}

#[test]
fn test_multi_proxy_config() {
    let content = r#"
[project]
name = "multi-proxy-test"

[[proxies]]
name = "frontend-proxy"
type = "caddy"
external_port = 80

[[proxies]]
name = "backend-proxy"
type = "nginx"
external_port = 8080

[[proxies]]
name = "api-proxy"
type = "haproxy"
external_port = 9000
algorithm = "roundrobin"
max_connections = 1024

[[services]]
name = "web-app"
domain = "app.example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    assert_eq!(config.proxies.len(), 3);
    assert_eq!(config.proxies[0].proxy_type, ProxyType::Caddy);
    assert_eq!(config.proxies[1].proxy_type, ProxyType::Nginx);
    assert_eq!(config.proxies[2].proxy_type, ProxyType::HaProxy);
    assert_eq!(config.proxies[2].algorithm, Some("roundrobin".to_string()));
    assert_eq!(config.proxies[2].max_connections, Some(1024));
}

#[test]
fn test_scaling_enabled_config() {
    let content = r#"
[project]
name = "scaling-test"
scaling = true

[[proxies]]
name = "load-balancer"
type = "haproxy"
external_port = 80
instances = 3
algorithm = "roundrobin"

[[services]]
name = "scalable-service"
domain = "scale.example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    assert!(config.project.scaling);
    assert_eq!(config.proxies[0].instances, 3);
}

#[test]
fn test_headers_configuration() {
    let content = r#"
[project]
name = "headers-test"

[[proxies]]
name = "header-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "header-service"
domain = "headers.example.com"
upstream = "http://192.0.2.1:3000"
headers_request_host = "backend.internal.com"
headers_request_authorization = "Bearer token123"
headers_response_cache_control = "public, max-age=3600"
headers_response_x_custom = "CustomValue"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    let service = &config.services[0];
    assert_eq!(service.headers.get("headers_request_host"), Some(&"backend.internal.com".to_string()));
    assert_eq!(service.headers.get("headers_request_authorization"), Some(&"Bearer token123".to_string()));
    assert_eq!(service.headers.get("headers_response_cache_control"), Some(&"public, max-age=3600".to_string()));
    assert_eq!(service.headers.get("headers_response_x_custom"), Some(&"CustomValue".to_string()));
}

#[test]
fn test_config_validation_empty_project_name() {
    let content = r#"
[project]
name = ""

[[proxies]]
name = "test-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "test-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let result = Config::load(temp_file.path());
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Project name cannot be empty"));
}

#[test]
fn test_config_validation_empty_proxy_name() {
    let content = r#"
[project]
name = "test-project"

[[proxies]]
name = ""
type = "caddy"
external_port = 80

[[services]]
name = "test-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let result = Config::load(temp_file.path());
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("name cannot be empty"));
}

#[test]
fn test_config_validation_zero_port() {
    let content = r#"
[project]
name = "test-project"

[[proxies]]
name = "test-proxy"
type = "caddy"
external_port = 0

[[services]]
name = "test-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let result = Config::load(temp_file.path());
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("external_port must be greater than 0"));
}

#[test]
fn test_config_validation_high_anubis_difficulty() {
    let content = r#"
[project]
name = "test-project"

[anubis]
enabled = true
difficulty = 15

[[proxies]]
name = "test-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "test-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let result = Config::load(temp_file.path());
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("difficulty must be between 1 and 10"));
}

#[test]
fn test_config_defaults() {
    let content = r#"
[project]
name = "defaults-test"

[[proxies]]
name = "test-proxy"
type = "caddy"
external_port = 80

[[services]]
name = "test-service"
domain = "example.com"
upstream = "http://192.0.2.1:3000"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");

    // Test default values
    assert!(!config.project.scaling);
    assert_eq!(config.global.auto_https, "off");
    assert_eq!(config.global.admin, "off");
    assert!(!config.tls.enabled);
    assert!(!config.anubis.enabled);
    assert_eq!(config.anubis.bind, ":8080");
    assert_eq!(config.anubis.difficulty, 5);
    assert_eq!(config.proxies[0].internal_port, 80);
    assert_eq!(config.proxies[0].instances, 1);
    assert!(!config.services[0].websocket);
    assert!(config.services[0].compress);
    assert_eq!(config.services[0].max_body_size, "1m");
    assert_eq!(config.logging.level, "INFO");
    assert_eq!(config.logging.format, "json");
}

#[test]
fn test_invalid_toml_syntax() {
    let content = r#"
[project
name = "invalid-toml"
"#;

    let temp_file = create_temp_config(content);
    let result = Config::load(temp_file.path());
    
    assert!(result.is_err());
    // Should be a TOML parsing error
    match result.unwrap_err() {
        CerberusError::TomlParse { .. } => {},
        _ => panic!("Expected TomlParse error"),
    }
}

#[test]
fn test_file_not_found() {
    let result = Config::load(&std::path::Path::new("/nonexistent/config.toml"));
    
    assert!(result.is_err());
    // Should be an I/O error
    match result.unwrap_err() {
        CerberusError::Io { .. } => {},
        _ => panic!("Expected Io error"),
    }
}