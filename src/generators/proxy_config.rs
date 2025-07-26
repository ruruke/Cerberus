//! # Proxy configuration generator
//!
//! Generates proxy configuration files (Caddy, Nginx, HAProxy, Traefik) from Cerberus configuration.

use crate::{
    Result,
    config::{Config, ProxyConfig, ServiceConfig},
};
use handlebars::Handlebars;
use serde_json::json;
use std::collections::HashMap;

/// Generator for proxy configurations
pub struct ProxyConfigGenerator<'a> {
    config: &'a Config,
    handlebars: Handlebars<'static>,
}

impl<'a> ProxyConfigGenerator<'a> {
    /// Create a new proxy configuration generator
    pub fn new(config: &'a Config) -> Self {
        let mut handlebars = Handlebars::new();
        
        // Register Caddy template
        handlebars.register_template_string("caddy", include_str!("../templates/Caddyfile.hbs"))
            .expect("Failed to register Caddy template");
            
        // Register Nginx template
        handlebars.register_template_string("nginx", include_str!("../templates/nginx.conf.hbs"))
            .expect("Failed to register Nginx template");
            
        // Register HAProxy template
        handlebars.register_template_string("haproxy", include_str!("../templates/haproxy.cfg.hbs"))
            .expect("Failed to register HAProxy template");
            
        // Register Traefik template
        handlebars.register_template_string("traefik", include_str!("../templates/traefik.yml.hbs"))
            .expect("Failed to register Traefik template");

        Self { config, handlebars }
    }

    /// Generate configuration for a specific proxy
    pub fn generate_for_proxy(&self, proxy: &ProxyConfig) -> Result<String> {
        match proxy.proxy_type.as_str() {
            "caddy" => self.generate_caddy_config(proxy),
            "nginx" => self.generate_nginx_config(proxy),
            "haproxy" => self.generate_haproxy_config(proxy),
            "traefik" => self.generate_traefik_config(proxy),
            _ => Err(crate::CerberusError::config(
                format!("Unsupported proxy type: {}", proxy.proxy_type)
            )),
        }
    }

    /// Generate Caddy configuration
    fn generate_caddy_config(&self, proxy: &ProxyConfig) -> Result<String> {
        let services = self.get_services_for_proxy(proxy);
        
        let template_data = json!({
            "proxy": proxy,
            "services": services,
            "project_name": &self.config.project.name,
            "external_port": proxy.external_port,
            "upstream": proxy.default_upstream.as_deref().unwrap_or("http://localhost:3000"),
            "has_services": !services.is_empty(),
            "has_anubis": self.config.anubis.enabled,
            "anubis_target": if self.config.anubis.enabled { &self.config.anubis.target } else { "" },
        });

        let config = self.handlebars.render("caddy", &template_data)?;
        Ok(config)
    }

    /// Generate Nginx configuration
    fn generate_nginx_config(&self, proxy: &ProxyConfig) -> Result<String> {
        let services = self.get_services_for_proxy(proxy);
        
        let template_data = json!({
            "proxy": proxy,
            "services": services,
            "project_name": &self.config.project.name,
            "external_port": proxy.external_port,
            "upstream": proxy.default_upstream.as_deref().unwrap_or("http://localhost:3000"),
            "has_services": !services.is_empty(),
            "worker_processes": "auto",
            "worker_connections": 1024,
            "keepalive_timeout": 65,
            "client_max_body_size": "100M",
        });

        let config = self.handlebars.render("nginx", &template_data)?;
        Ok(config)
    }

    /// Generate HAProxy configuration
    fn generate_haproxy_config(&self, proxy: &ProxyConfig) -> Result<String> {
        let services = self.get_services_for_proxy(proxy);
        
        let template_data = json!({
            "proxy": proxy,
            "services": services,
            "project_name": &self.config.project.name,
            "external_port": proxy.external_port,
            "upstream": proxy.default_upstream.as_deref().unwrap_or("http://localhost:3000"),
            "has_services": !services.is_empty(),
            "maxconn": 4096,
            "timeout_connect": "5s",
            "timeout_client": "50s",
            "timeout_server": "50s",
        });

        let config = self.handlebars.render("haproxy", &template_data)?;
        Ok(config)
    }

    /// Generate Traefik configuration
    fn generate_traefik_config(&self, proxy: &ProxyConfig) -> Result<String> {
        let services = self.get_services_for_proxy(proxy);
        
        let template_data = json!({
            "proxy": proxy,
            "services": services,
            "project_name": &self.config.project.name,
            "external_port": proxy.external_port,
            "upstream": proxy.default_upstream.as_deref().unwrap_or("http://localhost:3000"),
            "has_services": !services.is_empty(),
        });

        let config = self.handlebars.render("traefik", &template_data)?;
        Ok(config)
    }

    /// Get services that should be routed through this proxy
    fn get_services_for_proxy(&self, _proxy: &ProxyConfig) -> Vec<&ServiceConfig> {
        // For now, return all services. In the future, this could be filtered
        // based on proxy layer or other criteria
        self.config.services.iter().collect()
    }

    /// Generate all proxy configurations
    pub fn generate_all(&self) -> Result<HashMap<String, String>> {
        let mut configs = HashMap::new();
        
        for proxy in &self.config.proxies {
            let config = self.generate_for_proxy(proxy)?;
            configs.insert(proxy.name.clone(), config);
        }
        
        Ok(configs)
    }

    /// Get the appropriate file extension for a proxy type
    pub fn get_file_extension(proxy_type: &str) -> &'static str {
        match proxy_type {
            "caddy" => "Caddyfile",
            "nginx" => "nginx.conf",
            "haproxy" => "haproxy.cfg",
            "traefik" => "traefik.yml",
            _ => "conf",
        }
    }

    /// Generate Docker service configuration for proxy
    pub fn generate_docker_service(&self, proxy: &ProxyConfig) -> Result<serde_yaml::Value> {
        let docker_image = match proxy.proxy_type.as_str() {
            "caddy" => "caddy:2-alpine",
            "nginx" => "nginx:alpine",
            "haproxy" => "haproxy:alpine",
            "traefik" => "traefik:v3.0",
            _ => return Err(crate::CerberusError::config(
                format!("Unsupported proxy type for Docker: {}", proxy.proxy_type)
            )),
        };

        let config_path = format!("./built/proxy-configs/{}/", proxy.name);
        let config_file = Self::get_file_extension(proxy.proxy_type.as_str());
        
        let volumes = match proxy.proxy_type.as_str() {
            "caddy" => vec![
                format!("{}{}:/etc/caddy/Caddyfile:ro", config_path, config_file),
                "./built/logs:/var/log/caddy".to_string(),
            ],
            "nginx" => vec![
                format!("{}{}:/etc/nginx/nginx.conf:ro", config_path, config_file),
                "./built/logs:/var/log/nginx".to_string(),
            ],
            "haproxy" => vec![
                format!("{}{}:/usr/local/etc/haproxy/haproxy.cfg:ro", config_path, config_file),
                "./built/logs:/var/log/haproxy".to_string(),
            ],
            "traefik" => vec![
                format!("{}{}:/etc/traefik/traefik.yml:ro", config_path, config_file),
                "./built/logs:/var/log/traefik".to_string(),
            ],
            _ => vec![],
        };

        let ports = vec![format!("{}:{}", proxy.external_port, proxy.external_port)];

        let service = serde_yaml::to_value(&json!({
            "image": docker_image,
            "container_name": &proxy.name,
            "restart": "unless-stopped",
            "ports": ports,
            "volumes": volumes,
            "networks": ["cerberus-network"],
            "healthcheck": {
                "test": format!("wget --quiet --tries=1 --spider http://localhost:{}/health || exit 1", proxy.external_port),
                "interval": "30s",
                "timeout": "10s",
                "retries": 3,
                "start_period": "10s"
            },
            "labels": {
                "cerberus.component": "proxy",
                "cerberus.proxy": &proxy.name,
                "cerberus.proxy_type": &proxy.proxy_type
            },
            "depends_on": self.get_dependencies_for_proxy(proxy)
        }))?;

        Ok(service)
    }

    /// Get Docker service dependencies for a proxy
    fn get_dependencies_for_proxy(&self, proxy: &ProxyConfig) -> Vec<String> {
        let mut deps = Vec::new();
        
        // If this proxy routes to Anubis, add Anubis as dependency
        if self.config.anubis.enabled {
            if let Some(upstream) = &proxy.default_upstream {
                if upstream.contains("anubis") {
                    deps.push("anubis".to_string());
                }
            }
        }
        
        // Add other proxy dependencies based on upstream configuration
        for other_proxy in &self.config.proxies {
            if other_proxy.name != proxy.name {
                if let Some(upstream) = &proxy.default_upstream {
                    if upstream.contains(&other_proxy.name) {
                        deps.push(other_proxy.name.clone());
                    }
                }
            }
        }
        
        deps
    }
}
