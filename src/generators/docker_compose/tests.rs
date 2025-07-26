//! # Tests for Docker Compose generation
//!
//! These tests verify that Docker Compose YAML generation works correctly
//! for all supported configuration patterns and edge cases.

use super::*;
use crate::config::*;
use pretty_assertions::assert_eq;
use std::collections::HashMap;

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
        proxies: vec![ProxyConfig {
            name: "test-proxy".to_string(),
            proxy_type: ProxyType::Caddy,
            external_port: 80,
            internal_port: 80,
            layer: Some(1),
            instances: 1,
            algorithm: None,
            max_connections: None,
            default_upstream: None,
            routes: vec![],
        }],
        services: vec![ServiceConfig {
            name: "test-service".to_string(),
            domain: "test.example.com".to_string(),
            upstream: "http://192.0.2.1:3000".to_string(),
            websocket: false,
            compress: true,
            max_body_size: "1m".to_string(),
            headers: HashMap::new(),
        }],
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
    config.proxies = vec![
        ProxyConfig {
            name: "proxy-layer1".to_string(),
            proxy_type: ProxyType::Caddy,
            external_port: 80,
            internal_port: 80,
            layer: Some(1),
            instances: 1,
            algorithm: None,
            max_connections: None,
            default_upstream: Some("http://anubis:8080".to_string()),
            routes: vec![],
        },
        ProxyConfig {
            name: "proxy-layer2".to_string(),
            proxy_type: ProxyType::Caddy,
            external_port: 80,
            internal_port: 80,
            layer: Some(2),
            instances: 1,
            algorithm: None,
            max_connections: None,
            default_upstream: None,
            routes: vec![],
        },
    ];
    config
}

#[test]
fn test_minimal_docker_compose_generation() {
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);
    
    let result = generator.generate().expect("Generation should succeed");
    
    // Verify basic structure
    assert!(result.contains("version: '3.8'"));
    assert!(result.contains("services:"));
    assert!(result.contains("networks:"));
    assert!(result.contains("volumes:"));
    
    // Verify proxy service
    assert!(result.contains("test-proxy:"));
    assert!(result.contains("image: caddy:alpine"));
    assert!(result.contains("container_name: test-proxy"));
    assert!(result.contains("- \"80:80\""));
    
    // Verify networks
    assert!(result.contains("cerberus-front"));
    assert!(result.contains("cerberus-back"));
    
    // Should not contain Anubis when disabled
    assert!(!result.contains("anubis:"));
}

#[test]
fn test_anubis_enabled_docker_compose_generation() {
    let config = create_anubis_enabled_config();
    let generator = DockerComposeGenerator::new(&config);
    
    let result = generator.generate().expect("Generation should succeed");
    
    // Verify Anubis service is present
    assert!(result.contains("anubis:"));
    assert!(result.contains("image: chaitin/anubis:latest"));
    assert!(result.contains("container_name: anubis"));
    assert!(result.contains("- \"8080:8080\""));
    assert!(result.contains("- \"9090:9090\""));
    
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
    let generator = DockerComposeGenerator::new(&config);
    
    let result = generator.generate().expect("Generation should succeed");
    
    // Verify proxy-layer1 depends on anubis
    let proxy1_section = extract_service_section(&result, "proxy-layer1");
    assert!(proxy1_section.contains("depends_on:"));
    assert!(proxy1_section.contains("- anubis"));
    
    // Verify proxy-layer2 doesn't have dependencies
    let proxy2_section = extract_service_section(&result, "proxy-layer2");
    assert!(!proxy2_section.contains("depends_on:"));
    
    // Verify anubis depends on proxy-layer2
    let anubis_section = extract_service_section(&result, "anubis");
    assert!(anubis_section.contains("depends_on:"));
    assert!(anubis_section.contains("- proxy-layer2"));
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
    let config = create_minimal_config();
    let generator = DockerComposeGenerator::new(&config);
    
    let result = generator.generate().expect("Generation should succeed");
    
    // Verify healthcheck is present
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
    
    // Verify volume mounts
    assert!(result.contains("./proxy-configs/test-proxy:/etc/caddy:ro"));
    assert!(result.contains("./built/logs:/var/log/nginx:rw"));
    
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
    assert!(result.contains("subnet: 172.20.0.0/16"));
    assert!(result.contains("subnet: 172.21.0.0/16"));
}

#[test]
fn test_generation_with_empty_proxies() {
    let mut config = create_minimal_config();
    config.proxies.clear();
    
    let generator = DockerComposeGenerator::new(&config);
    let result = generator.generate().expect("Generation should succeed");
    
    // Should still have basic structure
    assert!(result.contains("version: '3.8'"));
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
    let _parsed: serde_yaml::Value = serde_yaml::from_str(&result)
        .expect("Generated YAML should be valid");
}

/// Helper function to extract a service section from docker-compose YAML
/// This is a simple string-based extraction for testing purposes
fn extract_service_section(yaml: &str, service_name: &str) -> String {
    let lines: Vec<&str> = yaml.lines().collect();
    let mut service_lines = Vec::new();
    let mut in_service = false;
    let mut service_indent = 0;
    
    for line in lines {
        if line.trim_start().starts_with(&format!("{}:", service_name)) {
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