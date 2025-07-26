//! # Tests for Docker Compose generation
//!
//! These tests verify that Docker Compose YAML generation works correctly
//! for all supported configuration patterns and edge cases.

use super::*;
use crate::config::*;
use pretty_assertions::assert_eq;
use std::collections::HashMap;

/// Helper function to create a default ProxyConfig
fn create_test_proxy(name: &str, proxy_type: ProxyType, external_port: u16) -> ProxyConfig {
    ProxyConfig {
        name: name.to_string(),
        proxy_type,
        external_port: Some(external_port),
        internal_port: 80,
        layer: Some(1),
        instances: 1,
        algorithm: None,
        max_connections: None,
        default_upstream: None,
        special_routing_service: None,
        routes: vec![],
        build_context: None,
        build_dockerfile: None,
        entrypoint: None,
        volumes: vec![],
        networks: vec![],
        restart: None,
        secrets: vec![],
        configs: vec![],
        depends_on: None,
        healthcheck: None,
        logging: None,
        deploy: None,
        environment: std::collections::HashMap::new(),
        env_file: vec![],
        expose: vec![],
        external_links: vec![],
        labels: std::collections::HashMap::new(),
    }
}

/// Helper function to create a minimal test configuration
fn create_minimal_config() -> Config {
    Config {
        project: ProjectConfig {
            name: "test-project".to_string(),
            scaling: false,
        },
        global: GlobalConfig::default(),
        tls: TlsConfig::default(),
        anubis: AnubisConfig::default(),
        proxies: vec![create_test_proxy("test-proxy", ProxyType::Caddy, 80)],
        services: vec![ServiceConfig {
            name: "test-service".to_string(),
            domain: "test.example.com".to_string(),
            upstream: "http://192.0.2.1:3000".to_string(),
            websocket: false,
            compress: true,
            max_body_size: "1m".to_string(),
            headers: HashMap::new(),
        }],
        networks: std::collections::HashMap::new(),
        volumes: std::collections::HashMap::new(),
        secrets: std::collections::HashMap::new(),
        configs: std::collections::HashMap::new(),
        logging: LoggingConfig::default(),
    }
}

/// Helper function to create a config with Anubis enabled
fn create_anubis_enabled_config() -> Config {
    let mut config = create_minimal_config();
    config.anubis.enabled = true;
    config.anubis.bind = ":8080".to_string();
    config.anubis.target = "http://proxy-2:80".to_string();
    config.anubis.difficulty = 5;
    config.anubis.metrics_bind = ":9090".to_string();
    config
}

/// Helper function to create a multi-proxy configuration
fn create_multi_proxy_config() -> Config {
    let mut config = create_minimal_config();
    let mut proxy1 = create_test_proxy("proxy-layer1", ProxyType::Caddy, 80);
    proxy1.default_upstream = Some("http://anubis:8080".to_string());
    
    let mut proxy2 = create_test_proxy("proxy-layer2", ProxyType::Caddy, 80);
    proxy2.layer = Some(2);
    
    config.proxies = vec![proxy1, proxy2];
    config
}

#[test]
fn test_minimal_docker_compose_generation() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify basic structure (no version in our current implementation)
    assert!(result.contains("services:"));
    assert!(result.contains("networks:"));
    assert!(result.contains("volumes:"));

    // Verify proxy service
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: caddy:alpine"));
    assert!(result.contains("container_name: test-proxy"));
    assert!(result.contains("- \"80:80\""));

    // Verify networks (current implementation)
    assert!(result.contains("test-project-front"));
    assert!(result.contains("test-project-back"));

    // Should not contain Anubis when disabled
    assert!(!result.contains("anubis:"));
}

#[test]
fn test_anubis_enabled_docker_compose_generation() {
    let mut config = create_anubis_enabled_config();
    // Make sure we have an nginx proxy for Anubis to work with
    config.proxies[0].proxy_type = ProxyType::Nginx;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify Anubis service is present (only when nginx proxy exists)
    assert!(result.contains("anubis:"));
    assert!(result.contains("image: ghcr.io/techarohq/anubis:latest"));
    assert!(result.contains("container_name: anubis"));

    // Verify Anubis environment variables
    assert!(result.contains("BIND=:8080"));
    assert!(result.contains("DIFFICULTY=5"));
    assert!(result.contains("TARGET=http://proxy-2:80"));
    assert!(result.contains("METRICS_BIND=:9090"));
}

#[test]
fn test_multi_proxy_docker_compose_generation() {
    let config = create_multi_proxy_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify both proxies are present
    assert!(result.contains("proxy-layer1:"));
    assert!(result.contains("proxy-layer2:"));

    // Verify both use Caddy image
    let caddy_count = result.matches("image: caddy:alpine").count();
    assert_eq!(caddy_count, 2);
}

#[test]
fn test_proxy_dependencies_no_anubis() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // When Anubis is disabled, proxy should not have depends_on for Anubis
    let proxy_section = extract_service_section(&result, "test-proxy");
    assert!(!proxy_section.contains("depends_on:"));
}

#[test]
fn test_proxy_dependencies_with_anubis() {
    let mut config = create_multi_proxy_config();
    config.anubis.enabled = true;
    // Make sure both proxies are nginx for Anubis to work
    config.proxies[0].proxy_type = ProxyType::Nginx;
    config.proxies[1].proxy_type = ProxyType::Nginx;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify proxy-layer1 depends on anubis (if it has anubis upstream)
    let proxy1_section = extract_service_section(&result, "proxy-layer1");
    if proxy1_section.contains("anubis:8080") {
        assert!(proxy1_section.contains("depends_on:"));
        assert!(proxy1_section.contains("- anubis"));
    }

    // Verify proxy-layer2 doesn't have dependencies
    let proxy2_section = extract_service_section(&result, "proxy-layer2");
    assert!(!proxy2_section.contains("depends_on:"));

    // Verify anubis depends on proxy-layer2 (when multiple proxies exist)
    let anubis_section = extract_service_section(&result, "anubis");
    if config.proxies.len() > 1 {
        assert!(anubis_section.contains("depends_on:"));
        assert!(anubis_section.contains("- proxy-layer2"));
    }
}

#[test]
fn test_scaling_configuration() {
    let mut config = create_minimal_config();
    config.project.scaling = true;
    config.proxies[0].instances = 3;

    let generator = DockerComposeGenerator::new(&config);
    let result = generator.generate().expect("Generation should succeed");

    // Verify scaled instances
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("test-proxy-2:"));
    assert!(result.contains("test-proxy-3:"));

    // Verify instance environment variables
    assert!(result.contains("INSTANCE_ID=2"));
    assert!(result.contains("INSTANCE_ID=3"));
}

#[test]
fn test_service_generation_external_ip() {
    let mut config = create_minimal_config();
    // External IP upstream should not generate a container
    config.services[0].upstream = "http://192.0.2.1:3000".to_string();

    let generator = DockerComposeGenerator::new(&config);
    let result = generator.generate().expect("Generation should succeed");

    // Should not contain a container for external service
    assert!(!result.contains("test-service:"));
}

#[test]
fn test_service_generation_internal_service() {
    let mut config = create_minimal_config();
    // Internal service name should generate a container
    config.services[0].upstream = "http://internal-service:3000".to_string();

    let generator = DockerComposeGenerator::new(&config);
    let result = generator.generate().expect("Generation should succeed");

    // Should contain a container for internal service
    assert!(result.contains("test-service:"));
    assert!(result.contains("image: alpine:latest"));
    assert!(result.contains("container_name: test-service"));
}

#[test]
fn test_environment_variables() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify proxy environment variables
    let proxy_section = extract_service_section(&result, "test-proxy");
    assert!(proxy_section.contains("PROXY_LAYER=1"));
    assert!(proxy_section.contains("MAX_CONNECTIONS=1024"));
}

#[test]
fn test_healthcheck_configuration() {
    let mut config = create_minimal_config();
    // Create a service with internal upstream to generate healthcheck
    config.services[0].upstream = "http://internal-service:3000".to_string();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify healthcheck is present for internal services
    assert!(result.contains("healthcheck:"));
    assert!(result.contains("test:"));
    assert!(result.contains("interval: 30s"));
    assert!(result.contains("timeout: 10s"));
    assert!(result.contains("retries: 3"));
}

#[test]
fn test_labels_configuration() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify labels are present
    assert!(result.contains("labels:"));
    assert!(result.contains("cerberus.service=proxy"));
    assert!(result.contains("cerberus.layer=1"));
    assert!(result.contains("cerberus.type=caddy"));
}

#[test]
fn test_volumes_configuration() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify volume mounts (current implementation uses :/etc/caddy:ro for Caddy)
    assert!(result.contains("./proxy-configs/test-proxy:/etc/caddy:ro"));
    assert!(result.contains("./built/logs:/var/log/caddy:rw"));

    // Verify named volumes
    assert!(result.contains("postgres_data:"));
    assert!(result.contains("redis_data:"));
    assert!(result.contains("nginx_logs:"));
}

#[test]
fn test_networks_configuration() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Verify network definitions
    assert!(result.contains("networks:"));
    assert!(result.contains("front-net:"));
    assert!(result.contains("back-net:"));
    assert!(result.contains("driver: bridge"));
    assert!(result.contains("subnet: 10.100.0.0/16"));
    assert!(result.contains("subnet: 10.101.0.0/16"));
}

#[test]
fn test_generation_with_empty_proxies() {
    let mut config = create_minimal_config();
    config.proxies.clear();

    let generator = DockerComposeGenerator::new(&config);
    let result = generator.generate().expect("Generation should succeed");

    // Should still have basic structure
    assert!(result.contains("services:"));
    assert!(result.contains("networks:"));
    assert!(result.contains("volumes:"));

    // But no proxy services
    assert!(!result.contains("image: caddy:alpine"));
}

#[test]
fn test_yaml_syntax_validity() {
    let config = create_anubis_enabled_config();
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Basic YAML syntax checks
    assert!(!result.contains("depends_on:\n\n")); // No empty depends_on
    assert!(!result.contains(": true")); // Booleans should be quoted
    assert!(!result.contains(": false")); // Booleans should be quoted

    // Should be parseable as YAML
    let _parsed: serde_yaml::Value =
        serde_yaml::from_str(&result).expect("Generated YAML should be valid");
}

/// Helper function to create config with specific proxy type
fn create_config_with_proxy_type(proxy_type: ProxyType) -> Config {
    let mut config = create_minimal_config();
    config.proxies[0].proxy_type = proxy_type;
    config
}

/// Helper function to create config with multiple proxy types
fn create_mixed_proxy_config() -> Config {
    let mut config = create_minimal_config();
    config.proxies = vec![
        create_test_proxy("nginx-proxy", ProxyType::Nginx, 80),
        create_test_proxy("caddy-proxy", ProxyType::Caddy, 81),
        create_test_proxy("haproxy-proxy", ProxyType::HaProxy, 82),
        create_test_proxy("traefik-proxy", ProxyType::Traefik, 83),
    ];
    config
}

#[test]
fn test_nginx_with_anubis_enabled() {
    let mut config = create_config_with_proxy_type(ProxyType::Nginx);
    config.anubis.enabled = true;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Nginx should generate proxy service when Anubis is enabled
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: nginx:alpine"));
    assert!(result.contains("anubis:"));
}

#[test]
fn test_nginx_with_anubis_disabled() {
    let mut config = create_config_with_proxy_type(ProxyType::Nginx);
    config.anubis.enabled = false;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Nginx should NOT generate proxy-1 when Anubis is disabled
    assert!(!result.contains("test-proxy:"));
    assert!(!result.contains("anubis:"));
}

#[test]
fn test_caddy_always_generates_simple_proxy() {
    let mut config = create_config_with_proxy_type(ProxyType::Caddy);
    config.anubis.enabled = false; // Even when Anubis is disabled
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Caddy should always generate as simple reverse proxy
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: caddy:alpine"));
    assert!(!result.contains("anubis:")); // No Anubis for non-nginx proxies
}

#[test]
fn test_haproxy_always_generates_simple_proxy() {
    let mut config = create_config_with_proxy_type(ProxyType::HaProxy);
    config.anubis.enabled = true; // Even when Anubis is enabled
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // HAProxy should always generate as simple reverse proxy
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: haproxy:alpine"));
    assert!(!result.contains("anubis:")); // No Anubis for non-nginx proxies
}

#[test]
fn test_traefik_always_generates_simple_proxy() {
    let mut config = create_config_with_proxy_type(ProxyType::Traefik);
    config.anubis.enabled = true; // Even when Anubis is enabled
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // Traefik should always generate as simple reverse proxy
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: traefik:v3.0"));
    assert!(!result.contains("anubis:")); // No Anubis for non-nginx proxies
}

#[test]
fn test_mixed_proxy_types_with_anubis() {
    let mut config = create_mixed_proxy_config();
    config.anubis.enabled = true;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // All proxy types should generate
    assert!(result.contains("nginx-proxy:"));
    assert!(result.contains("caddy-proxy:"));
    assert!(result.contains("haproxy-proxy:"));
    assert!(result.contains("traefik-proxy:"));

    // Anubis should only generate because nginx is present
    assert!(result.contains("anubis:"));

    // Verify images
    assert!(result.contains("image: nginx:alpine"));
    assert!(result.contains("image: caddy:alpine"));
    assert!(result.contains("image: haproxy:alpine"));
    assert!(result.contains("image: traefik:v3.0"));
}

#[test]
fn test_mixed_proxy_types_without_nginx() {
    let mut config = create_minimal_config();
    config.proxies = vec![
        create_test_proxy("caddy-proxy", ProxyType::Caddy, 81),
        create_test_proxy("haproxy-proxy", ProxyType::HaProxy, 82),
        create_test_proxy("traefik-proxy", ProxyType::Traefik, 83),
    ];
    config.anubis.enabled = true;
    let generator = DockerComposeGenerator::new(&config);

    let result = generator.generate().expect("Generation should succeed");

    // All non-nginx proxies should generate
    assert!(result.contains("caddy-proxy:"));
    assert!(result.contains("haproxy-proxy:"));
    assert!(result.contains("traefik-proxy:"));

    // No Anubis should generate because no nginx proxies
    assert!(!result.contains("anubis:"));
}

/// Helper function to extract a service section from docker-compose YAML
/// This is a simple string-based extraction for testing purposes
fn extract_service_section(yaml: &str, service_name: &str) -> String {
    let lines: Vec<&str> = yaml.lines().collect();
    let mut service_lines = Vec::new();
    let mut in_service = false;
    let mut service_indent = 0;

    for line in lines {
        if line.trim_start().starts_with(&format!("{service_name}:")) {
            in_service = true;
            service_indent = line.len() - line.trim_start().len();
            service_lines.push(line);
        } else if in_service {
            let current_indent = line.len() - line.trim_start().len();
            if !line.trim().is_empty() && current_indent <= service_indent {
                // Next service or section started
                break;
            }
            service_lines.push(line);
        }
    }

    service_lines.join("\n")
}
