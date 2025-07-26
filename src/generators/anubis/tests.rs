//! Tests for Anubis configuration generator

use crate::config::{Config, ProjectConfig, AnubisConfig};
use crate::generators::anubis::AnubisGenerator;
use pretty_assertions::assert_eq;
use serde_json::Value;
use std::collections::HashMap;

/// Create a test configuration with Anubis enabled
fn create_test_config() -> Config {
    Config {
        project: ProjectConfig {
            name: "test-project".to_string(),
            scaling: false,
        },
        proxies: vec![],
        services: vec![],
        anubis: Some(AnubisConfig {
            enabled: true,
            bind: ":8080".to_string(),
            target: "http://proxy-layer2:80".to_string(),
            difficulty: 7,
            metrics_bind: ":9090".to_string(),
        }),
    }
}

/// Create a test configuration without Anubis
fn create_test_config_without_anubis() -> Config {
    Config {
        project: ProjectConfig {
            name: "test-project-no-anubis".to_string(),
            scaling: false,
        },
        proxies: vec![],
        services: vec![],
        anubis: None,
    }
}

#[test]
fn test_anubis_generator_creation() {
    let config = create_test_config();
    let generator = AnubisGenerator::new(&config);
    
    // Test that generator can be created successfully
    assert_eq!(generator.config.project.name, "test-project");
}

#[test]
fn test_generate_bot_policy_json() {
    let config = create_test_config();
    let generator = AnubisGenerator::new(&config);
    
    let result = generator.generate().expect("Failed to generate bot policy");
    
    // Parse the generated JSON to validate structure
    let policy: Value = serde_json::from_str(&result).expect("Generated JSON is invalid");
    
    // Check that main sections exist
    assert!(policy["ALLOW"].is_array(), "ALLOW section should be an array");
    assert!(policy["CHALLENGE"].is_array(), "CHALLENGE section should be an array");
    assert!(policy["BLOCK"].is_array(), "BLOCK section should be an array");
    assert!(policy["config"].is_object(), "config section should be an object");
    assert!(policy["metadata"].is_object(), "metadata section should be an object");
    
    // Check specific ALLOW rules
    let allow_rules = policy["ALLOW"].as_array().unwrap();
    let favicon_rule = allow_rules.iter().find(|rule| {
        rule["path"] == "/favicon.ico"
    });
    assert!(favicon_rule.is_some(), "Should have favicon rule");
    
    let googlebot_rule = allow_rules.iter().find(|rule| {
        rule["user-agent"] == "*Googlebot*"
    });
    assert!(googlebot_rule.is_some(), "Should have Googlebot rule");
    
    // Check CHALLENGE rules
    let challenge_rules = policy["CHALLENGE"].as_array().unwrap();
    let mozilla_rule = challenge_rules.iter().find(|rule| {
        rule["user-agent"] == "Mozilla*"
    });
    assert!(mozilla_rule.is_some(), "Should have Mozilla challenge rule");
    
    // Check BLOCK rules
    let block_rules = policy["BLOCK"].as_array().unwrap();
    let bot_rule = block_rules.iter().find(|rule| {
        rule["user-agent"] == "*bot*"
    });
    assert!(bot_rule.is_some(), "Should have bot blocking rule");
    
    // Check config values
    assert_eq!(policy["config"]["difficulty"], 7, "Difficulty should match config");
    assert_eq!(policy["config"]["challenge_ttl"], 3600, "TTL should be set");
    assert_eq!(policy["config"]["javascript_challenge"], true, "JS challenge should be enabled");
    
    // Check metadata
    assert_eq!(policy["metadata"]["generated_by"], "cerberus-rust");
    assert_eq!(policy["metadata"]["project_name"], "test-project");
    assert_eq!(policy["metadata"]["anubis_enabled"], true);
}

#[test]
fn test_generate_bot_policy_without_anubis() {
    let config = create_test_config_without_anubis();
    let generator = AnubisGenerator::new(&config);
    
    let result = generator.generate().expect("Failed to generate bot policy");
    let policy: Value = serde_json::from_str(&result).expect("Generated JSON is invalid");
    
    // Should still generate valid policy with default values
    assert_eq!(policy["config"]["difficulty"], 5, "Should use default difficulty");
    assert_eq!(policy["metadata"]["anubis_enabled"], false);
    assert_eq!(policy["metadata"]["project_name"], "test-project-no-anubis");
}

#[test]
fn test_generate_env_config() {
    let config = create_test_config();
    let generator = AnubisGenerator::new(&config);
    
    let env_vars = generator.generate_env_config().expect("Failed to generate env config");
    
    // Check that all required environment variables are present
    let env_map: HashMap<String, String> = env_vars
        .iter()
        .filter_map(|var| {
            let parts: Vec<&str> = var.splitn(2, '=').collect();
            if parts.len() == 2 {
                Some((parts[0].to_string(), parts[1].to_string()))
            } else {
                None
            }
        })
        .collect();
    
    assert_eq!(env_map.get("ANUBIS_BIND"), Some(&":8080".to_string()));
    assert_eq!(env_map.get("ANUBIS_TARGET"), Some(&"http://proxy-layer2:80".to_string()));
    assert_eq!(env_map.get("ANUBIS_DIFFICULTY"), Some(&"7".to_string()));
    assert_eq!(env_map.get("ANUBIS_METRICS_BIND"), Some(&":9090".to_string()));
    assert_eq!(env_map.get("ANUBIS_LOG_LEVEL"), Some(&"INFO".to_string()));
    assert_eq!(env_map.get("ANUBIS_CHALLENGE_TTL"), Some(&"3600".to_string()));
}

#[test]
fn test_generate_env_config_without_anubis() {
    let config = create_test_config_without_anubis();
    let generator = AnubisGenerator::new(&config);
    
    let result = generator.generate_env_config();
    assert!(result.is_err(), "Should fail when Anubis config is missing");
    
    let error = result.unwrap_err();
    assert!(error.to_string().contains("Anubis configuration not found"));
}

#[test]
fn test_generate_docker_service() {
    let config = create_test_config();
    let generator = AnubisGenerator::new(&config);
    
    let service = generator.generate_docker_service().expect("Failed to generate Docker service");
    
    // Check service configuration
    assert_eq!(service["image"], "ghcr.io/chaitin/anubis:latest");
    assert_eq!(service["container_name"], "anubis");
    assert_eq!(service["restart"], "unless-stopped");
    
    // Check ports
    let ports = service["ports"].as_sequence().unwrap();
    assert!(ports.contains(&serde_yaml::Value::String("8080:8080".to_string())));
    assert!(ports.contains(&serde_yaml::Value::String("9090:9090".to_string())));
    
    // Check volumes
    let volumes = service["volumes"].as_sequence().unwrap();
    assert!(volumes.iter().any(|v| v.as_str().unwrap().contains("botPolicy.json")));
    assert!(volumes.iter().any(|v| v.as_str().unwrap().contains("/app/logs")));
    
    // Check networks
    let networks = service["networks"].as_sequence().unwrap();
    assert!(networks.contains(&serde_yaml::Value::String("cerberus-network".to_string())));
    
    // Check healthcheck
    assert!(service["healthcheck"]["test"].as_str().unwrap().contains("curl"));
    assert_eq!(service["healthcheck"]["interval"], "30s");
    assert_eq!(service["healthcheck"]["timeout"], "10s");
    assert_eq!(service["healthcheck"]["retries"], 3);
    
    // Check labels
    assert_eq!(service["labels"]["cerberus.component"], "ddos-protection");
    assert_eq!(service["labels"]["cerberus.proxy"], "anubis");
}

#[test]
fn test_generate_docker_service_without_anubis() {
    let config = create_test_config_without_anubis();
    let generator = AnubisGenerator::new(&config);
    
    let result = generator.generate_docker_service();
    assert!(result.is_err(), "Should fail when Anubis config is missing");
}

#[test]
fn test_bot_policy_json_structure() {
    let config = create_test_config();
    let generator = AnubisGenerator::new(&config);
    
    let result = generator.generate().expect("Failed to generate bot policy");
    let policy: Value = serde_json::from_str(&result).expect("Generated JSON is invalid");
    
    // Verify JSON structure is well-formed and contains expected fields
    assert!(policy.is_object(), "Root should be an object");
    
    // Check ALLOW section structure
    let allow_section = &policy["ALLOW"];
    assert!(allow_section.is_array(), "ALLOW should be array");
    let first_allow_rule = &allow_section[0];
    assert!(first_allow_rule.is_object(), "Allow rules should be objects");
    assert!(first_allow_rule.get("description").is_some(), "Allow rules should have descriptions");
    
    // Check CHALLENGE section structure
    let challenge_section = &policy["CHALLENGE"];
    assert!(challenge_section.is_array(), "CHALLENGE should be array");
    
    // Check for rate limiting in challenge rules
    let rate_limit_rule = challenge_section.as_array().unwrap().iter().find(|rule| {
        rule.get("rate_limit").is_some()
    });
    assert!(rate_limit_rule.is_some(), "Should have rate limiting rule");
    
    // Check BLOCK section structure
    let block_section = &policy["BLOCK"];
    assert!(block_section.is_array(), "BLOCK should be array");
    
    // Ensure no overlapping patterns between ALLOW and BLOCK
    let allow_user_agents: Vec<&str> = allow_section.as_array().unwrap()
        .iter()
        .filter_map(|rule| rule.get("user-agent")?.as_str())
        .collect();
    
    let block_user_agents: Vec<&str> = block_section.as_array().unwrap()
        .iter()
        .filter_map(|rule| rule.get("user-agent")?.as_str())
        .collect();
    
    // Verify legitimate crawlers are in ALLOW, not BLOCK
    assert!(allow_user_agents.contains(&"*Googlebot*"));
    assert!(allow_user_agents.contains(&"*bingbot*"));
    assert!(!block_user_agents.contains(&"*Googlebot*"));
    assert!(!block_user_agents.contains(&"*bingbot*"));
}

#[test]
fn test_anubis_config_validation() {
    let mut config = create_test_config();
    
    // Test with different difficulty levels
    for difficulty in [1, 5, 10] {
        config.anubis.as_mut().unwrap().difficulty = difficulty;
        let generator = AnubisGenerator::new(&config);
        let result = generator.generate().expect("Failed to generate with difficulty {difficulty}");
        let policy: Value = serde_json::from_str(&result).expect("Invalid JSON");
        assert_eq!(policy["config"]["difficulty"], difficulty);
    }
    
    // Test with different bind addresses
    let bind_addresses = [":8080", ":8443", ":3000"];
    for bind in bind_addresses {
        config.anubis.as_mut().unwrap().bind = bind.to_string();
        let generator = AnubisGenerator::new(&config);
        let env_vars = generator.generate_env_config().expect("Failed to generate env config");
        assert!(env_vars.iter().any(|var| var == &format!("ANUBIS_BIND={bind}")));
    }
}