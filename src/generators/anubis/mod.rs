//! # Anubis configuration generator
//!
//! Generates Anubis DDoS protection configuration from Cerberus settings.

use crate::{Result, config::Config};
use serde_json::json;

/// Generator for Anubis configurations
pub struct AnubisGenerator<'a> {
    config: &'a Config,
}

impl<'a> AnubisGenerator<'a> {
    /// Create a new Anubis configuration generator
    pub fn new(config: &'a Config) -> Self {
        Self { config }
    }

    /// Generate Anubis bot policy JSON configuration
    pub fn generate(&self) -> Result<String> {
        // Default bot policy that allows legitimate crawlers and challenges suspicious traffic
        let bot_policy = json!({
            "ALLOW": [
                {
                    "path": "/favicon.ico",
                    "description": "Allow favicon requests"
                },
                {
                    "path": "/.well-known/*",
                    "description": "Allow well-known paths for certificates, etc."
                },
                {
                    "path": "/robots.txt",
                    "description": "Allow robots.txt"
                },
                {
                    "user-agent": "*Googlebot*",
                    "description": "Allow Google crawlers"
                },
                {
                    "user-agent": "*bingbot*",
                    "description": "Allow Bing crawlers"
                },
                {
                    "user-agent": "*facebookexternalhit*",
                    "description": "Allow Facebook link previews"
                },
                {
                    "user-agent": "*Twitterbot*",
                    "description": "Allow Twitter link previews"
                },
                {
                    "user-agent": "*LinkedInBot*",
                    "description": "Allow LinkedIn link previews"
                },
                {
                    "user-agent": "*Slackbot*",
                    "description": "Allow Slack link previews"
                }
            ],
            "CHALLENGE": [
                {
                    "user-agent": "Mozilla*",
                    "description": "Challenge typical browser user agents"
                },
                {
                    "user-agent": "*Chrome*",
                    "description": "Challenge Chrome browsers"
                },
                {
                    "user-agent": "*Firefox*",
                    "description": "Challenge Firefox browsers"
                },
                {
                    "user-agent": "*Safari*",
                    "description": "Challenge Safari browsers"
                },
                {
                    "user-agent": "*Edge*",
                    "description": "Challenge Edge browsers"
                },
                {
                    "path": "/*",
                    "rate_limit": {
                        "requests_per_minute": 60,
                        "burst": 10
                    },
                    "description": "Rate limit all paths"
                }
            ],
            "BLOCK": [
                {
                    "user-agent": "*bot*",
                    "description": "Block generic bots"
                },
                {
                    "user-agent": "*crawler*",
                    "description": "Block generic crawlers"
                },
                {
                    "user-agent": "*scraper*",
                    "description": "Block scrapers"
                },
                {
                    "user-agent": "*wget*",
                    "description": "Block wget"
                },
                {
                    "user-agent": "*curl*",
                    "description": "Block curl"
                },
                {
                    "user-agent": "*python*",
                    "description": "Block Python requests"
                },
                {
                    "path": "/admin*",
                    "description": "Block admin paths"
                },
                {
                    "path": "/.env*",
                    "description": "Block environment files"
                },
                {
                    "path": "/wp-*",
                    "description": "Block WordPress paths"
                }
            ],
            "config": {
                "difficulty": self.config.anubis.difficulty,
                "challenge_ttl": 3600,
                "rate_limit_window": 60,
                "max_challenge_attempts": 3,
                "javascript_challenge": true,
                "proof_of_work": true
            },
            "metadata": {
                "generated_by": "cerberus-rust",
                "version": "1.0.0",
                "project_name": &self.config.project.name,
                "anubis_enabled": self.config.anubis.enabled
            }
        });

        // Pretty print JSON for readability
        Ok(serde_json::to_string_pretty(&bot_policy)?)
    }

    /// Generate Anubis environment configuration for Docker
    pub fn generate_env_config(&self) -> Result<Vec<String>> {
        let anubis_config = &self.config.anubis;

        let env_vars = vec![
            format!("ANUBIS_BIND={}", anubis_config.bind),
            format!("ANUBIS_TARGET={}", anubis_config.target),
            format!("ANUBIS_DIFFICULTY={}", anubis_config.difficulty),
            format!("ANUBIS_METRICS_BIND={}", anubis_config.metrics_bind),
            "ANUBIS_LOG_LEVEL=INFO".to_string(),
            "ANUBIS_CHALLENGE_TTL=3600".to_string(),
            "ANUBIS_RATE_LIMIT_WINDOW=60".to_string(),
            "ANUBIS_MAX_CHALLENGE_ATTEMPTS=3".to_string(),
            "USE_REMOTE_ADDRESS=true".to_string(),
        ];

        Ok(env_vars)
    }

    /// Generate Anubis Docker service configuration
    pub fn generate_docker_service(&self) -> Result<serde_yaml::Value> {
        let anubis_config = &self.config.anubis;

        let env_vars = self.generate_env_config()?;

        let service = serde_yaml::to_value(json!({
            "image": "ghcr.io/chaitin/anubis:latest",
            "container_name": "anubis",
            "restart": "unless-stopped",
            "environment": env_vars,
            "ports": [
                format!("{}:8080", anubis_config.bind.trim_start_matches(':')),
                format!("{}:9090", anubis_config.metrics_bind.trim_start_matches(':'))
            ],
            "volumes": [
                "./built/anubis/botPolicy.json:/app/botPolicy.json:ro",
                "./built/logs:/app/logs"
            ],
            "networks": ["cerberus-network"],
            "healthcheck": {
                "test": format!("curl -f http://localhost{}/health || exit 1", anubis_config.bind),
                "interval": "30s",
                "timeout": "10s",
                "retries": 3,
                "start_period": "10s"
            },
            "labels": {
                "cerberus.component": "ddos-protection",
                "cerberus.proxy": "anubis"
            }
        }))?;

        Ok(service)
    }
}
