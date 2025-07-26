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
    file.write_all(content.as_bytes())
        .expect("Failed to write to temp file");
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
    assert_eq!(config.proxies[0].external_port, Some(80));
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
    assert_eq!(
        config.proxies[0].routes[1].route_type,
        RouteType::Conditional
    );
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
    assert_eq!(
        service.headers.get("headers_request_host"),
        Some(&"backend.internal.com".to_string())
    );
    assert_eq!(
        service.headers.get("headers_request_authorization"),
        Some(&"Bearer token123".to_string())
    );
    assert_eq!(
        service.headers.get("headers_response_cache_control"),
        Some(&"public, max-age=3600".to_string())
    );
    assert_eq!(
        service.headers.get("headers_response_x_custom"),
        Some(&"CustomValue".to_string())
    );
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
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("Project name cannot be empty")
    );
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
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("name cannot be empty")
    );
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
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("external_port must be greater than 0")
    );
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
    assert!(
        result
            .unwrap_err()
            .to_string()
            .contains("difficulty must be between 1 and 10")
    );
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
        CerberusError::TomlParse { .. } => {}
        _ => panic!("Expected TomlParse error"),
    }
}

#[test]
fn test_file_not_found() {
    let result = Config::load(std::path::Path::new("/nonexistent/config.toml"));

    assert!(result.is_err());
    // Should be an I/O error
    match result.unwrap_err() {
        CerberusError::Io { .. } => {}
        _ => panic!("Expected Io error"),
    }
}

#[test]
fn test_secrets_configuration() {
    let content = r#"
[project]
name = "secrets-test"

[secrets.db_password]
file = "./secrets/db_password.txt"

[secrets.oauth_token]
environment = "OAUTH_TOKEN"

[secrets.api_key]
content = "super-secret-key"

[secrets.external_secret]
external = true
name = "production-secret"

[[proxies]]
name = "test-proxy"
type = "nginx"
external_port = 80
secrets = [
    "db_password",
    { source = "api_key", target = "/run/secrets/api_key", mode = 400 }
]
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");
    
    // Check secrets configuration
    assert_eq!(config.secrets.len(), 4);
    
    // Test file-based secret
    if let Some(crate::config::SecretConfig::File { file }) = config.secrets.get("db_password") {
        assert_eq!(file, "./secrets/db_password.txt");
    } else {
        panic!("Expected file-based secret");
    }
    
    // Test environment secret
    if let Some(crate::config::SecretConfig::Environment { environment }) = config.secrets.get("oauth_token") {
        assert_eq!(environment, "OAUTH_TOKEN");
    } else {
        panic!("Expected environment secret");
    }
    
    // Test content secret
    if let Some(crate::config::SecretConfig::Content { content }) = config.secrets.get("api_key") {
        assert_eq!(content, "super-secret-key");
    } else {
        panic!("Expected content secret");
    }
    
    // Check proxy secrets references
    let proxy = &config.proxies[0];
    assert_eq!(proxy.secrets.len(), 2);
    
    if let crate::config::ServiceSecretRef::Simple(name) = &proxy.secrets[0] {
        assert_eq!(name, "db_password");
    } else {
        panic!("Expected simple secret reference");
    }
    
    if let crate::config::ServiceSecretRef::Detailed { source, target, mode, .. } = &proxy.secrets[1] {
        assert_eq!(source, "api_key");
        assert_eq!(target.as_ref().unwrap(), "/run/secrets/api_key");
        assert_eq!(*mode, Some(400));
    } else {
        panic!("Expected detailed secret reference");
    }
}

#[test]
fn test_configs_configuration() {
    let content = r#"
[project]
name = "configs-test"

[configs.app_config]
file = "./configs/app.conf"

[configs.dynamic_config]
content = '''
debug=true
log_level=info
'''

[[proxies]]
name = "test-proxy"
type = "nginx"
external_port = 80
configs = [
    "app_config",
    { source = "dynamic_config", target = "/etc/app/config.ini" }
]
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");
    
    // Check configs configuration
    assert_eq!(config.configs.len(), 2);
    
    // Test file-based config
    if let Some(crate::config::ConfigFileConfig::File { file }) = config.configs.get("app_config") {
        assert_eq!(file, "./configs/app.conf");
    } else {
        panic!("Expected file-based config");
    }
    
    // Test content config
    if let Some(crate::config::ConfigFileConfig::Content { content }) = config.configs.get("dynamic_config") {
        assert!(content.contains("debug=true"));
        assert!(content.contains("log_level=info"));
    } else {
        panic!("Expected content config");
    }
    
    // Check proxy configs references
    let proxy = &config.proxies[0];
    assert_eq!(proxy.configs.len(), 2);
}

#[test]
fn test_networks_configuration() {
    let content = r#"
[project]
name = "networks-test"

[networks.frontend]
driver = "bridge"
enable_ipv6 = true

[networks.backend]
driver = "overlay"

[networks.backend.ipam]
driver = "default"

[[networks.backend.ipam.config]]
subnet = "172.20.0.0/16"
gateway = "172.20.0.1"

[networks.external_net]
external = true
name = "existing-network"

[[proxies]]
name = "test-proxy"
type = "nginx"
external_port = 80
networks = ["frontend", "backend"]
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");
    
    // Check networks configuration
    assert_eq!(config.networks.len(), 3);
    
    // Test frontend network
    let frontend = config.networks.get("frontend").unwrap();
    assert_eq!(frontend.driver, "bridge");
    assert!(frontend.enable_ipv6);
    
    // Test backend network with IPAM
    let backend = config.networks.get("backend").unwrap();
    assert_eq!(backend.driver, "overlay");
    assert!(backend.ipam.is_some());
    
    if let Some(ipam) = &backend.ipam {
        assert_eq!(ipam.config.len(), 1);
        assert_eq!(ipam.config[0].subnet.as_ref().unwrap(), "172.20.0.0/16");
        assert_eq!(ipam.config[0].gateway.as_ref().unwrap(), "172.20.0.1");
    }
    
    // Test external network
    let external = config.networks.get("external_net").unwrap();
    assert!(external.external);
    assert_eq!(external.name.as_ref().unwrap(), "existing-network");
    
    // Check proxy networks
    let proxy = &config.proxies[0];
    assert_eq!(proxy.networks, vec!["frontend", "backend"]);
}

#[test]
fn test_volumes_configuration() {
    let content = r#"
[project]
name = "volumes-test"

[volumes.db_data]
driver = "local"

[volumes.shared_storage]
external = true
name = "shared-volume"

[volumes.cache_data.driver_opts]
type = "tmpfs"
device = "tmpfs"

[[proxies]]
name = "test-proxy"
type = "nginx"
external_port = 80
volumes = [
    "db_data:/var/lib/mysql",
    "shared_storage:/mnt/shared:ro"
]
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");
    
    // Check volumes configuration
    assert_eq!(config.volumes.len(), 3);
    
    // Test local volume
    let db_data = config.volumes.get("db_data").unwrap();
    assert_eq!(db_data.driver.as_ref().unwrap(), "local");
    
    // Test external volume
    let shared = config.volumes.get("shared_storage").unwrap();
    assert!(shared.external);
    assert_eq!(shared.name.as_ref().unwrap(), "shared-volume");
    
    // Test volume with driver options
    let cache = config.volumes.get("cache_data").unwrap();
    assert_eq!(cache.driver_opts.get("type").unwrap(), "tmpfs");
    assert_eq!(cache.driver_opts.get("device").unwrap(), "tmpfs");
    
    // Check proxy volumes
    let proxy = &config.proxies[0];
    assert_eq!(proxy.volumes.len(), 2);
    assert_eq!(proxy.volumes[0], "db_data:/var/lib/mysql");
    assert_eq!(proxy.volumes[1], "shared_storage:/mnt/shared:ro");
}

#[test]
fn test_comprehensive_docker_features() {
    let content = r#"
[project]
name = "comprehensive-test"

# Secrets
[secrets.db_password]
file = "./secrets/db_password"

# Configs
[configs.nginx_conf]
file = "./configs/nginx.conf"

# Networks
[networks.web]
driver = "bridge"

[networks.db]
driver = "bridge"

# Volumes
[volumes.mysql_data]
driver = "local"

[[proxies]]
name = "web-proxy"
type = "nginx"
external_port = 80
internal_port = 80
build_context = "./nginx"
build_dockerfile = "Dockerfile"
restart = "unless-stopped"
networks = ["web", "db"]
volumes = ["./nginx.conf:/etc/nginx/nginx.conf:ro"]
secrets = ["db_password"]
configs = ["nginx_conf"]

[proxies.environment]
NGINX_HOST = "localhost"
NGINX_PORT = "80"

[proxies.healthcheck]
test = ["CMD", "curl", "-f", "http://localhost/health"]
interval = "30s"
timeout = "10s"
retries = 3

[proxies.deploy]
replicas = 2

[proxies.deploy.resources.limits]
cpus = "0.5"
memory = "512M"

[proxies.deploy.update_config]
parallelism = 1
delay = "10s"
failure_action = "rollback"
"#;

    let temp_file = create_temp_config(content);
    let config = Config::load(temp_file.path()).expect("Failed to load config");
    
    // Basic checks
    assert_eq!(config.project.name, "comprehensive-test");
    assert_eq!(config.secrets.len(), 1);
    assert_eq!(config.configs.len(), 1);
    assert_eq!(config.networks.len(), 2);
    assert_eq!(config.volumes.len(), 1);
    assert_eq!(config.proxies.len(), 1);
    
    let proxy = &config.proxies[0];
    
    // Check proxy configuration
    assert_eq!(proxy.name, "web-proxy");
    assert_eq!(proxy.external_port, Some(80));
    assert_eq!(proxy.build_context.as_ref().unwrap(), "./nginx");
    assert_eq!(proxy.restart.as_ref().unwrap(), "unless-stopped");
    
    // Check networks and volumes
    assert_eq!(proxy.networks, vec!["web", "db"]);
    assert_eq!(proxy.volumes.len(), 1);
    
    // Check secrets and configs
    assert_eq!(proxy.secrets.len(), 1);
    assert_eq!(proxy.configs.len(), 1);
    
    // Check environment
    assert_eq!(proxy.environment.get("NGINX_HOST").unwrap(), "localhost");
    assert_eq!(proxy.environment.get("NGINX_PORT").unwrap(), "80");
    
    // Check healthcheck
    assert!(proxy.healthcheck.is_some());
    if let Some(hc) = &proxy.healthcheck {
        assert_eq!(hc.test, vec!["CMD", "curl", "-f", "http://localhost/health"]);
        assert_eq!(hc.interval, "30s");
        assert_eq!(hc.retries, 3);
    }
    
    // Check deploy configuration
    assert!(proxy.deploy.is_some());
    if let Some(deploy) = &proxy.deploy {
        assert_eq!(deploy.replicas, Some(2));
        
        if let Some(resources) = &deploy.resources {
            if let Some(limits) = &resources.limits {
                assert_eq!(limits.cpus.as_ref().unwrap(), "0.5");
                assert_eq!(limits.memory.as_ref().unwrap(), "512M");
            }
        }
        
        if let Some(update_config) = &deploy.update_config {
            assert_eq!(update_config.parallelism, Some(1));
            assert_eq!(update_config.delay.as_ref().unwrap(), "10s");
            assert_eq!(update_config.failure_action.as_ref().unwrap(), "rollback");
        }
    }
}
