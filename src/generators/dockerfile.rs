//! # Dockerfile generator
//!
//! Generates Dockerfiles for proxy services from Cerberus configuration.

use crate::{
    Result,
    config::{Config, ProxyConfig},
};
use handlebars::Handlebars;
use serde_json::json;
use std::collections::HashMap;

/// Generator for Dockerfiles
pub struct DockerfileGenerator<'a> {
    config: &'a Config,
    handlebars: Handlebars<'static>,
}

impl<'a> DockerfileGenerator<'a> {
    /// Create a new Dockerfile generator
    pub fn new(config: &'a Config) -> Self {
        let mut handlebars = Handlebars::new();
        
        // Register Dockerfile templates for different proxy types
        handlebars.register_template_string("caddy_dockerfile", include_str!("../templates/Dockerfile.caddy.hbs"))
            .expect("Failed to register Caddy Dockerfile template");
            
        handlebars.register_template_string("nginx_dockerfile", include_str!("../templates/Dockerfile.nginx.hbs"))
            .expect("Failed to register Nginx Dockerfile template");
            
        handlebars.register_template_string("haproxy_dockerfile", include_str!("../templates/Dockerfile.haproxy.hbs"))
            .expect("Failed to register HAProxy Dockerfile template");
            
        handlebars.register_template_string("traefik_dockerfile", include_str!("../templates/Dockerfile.traefik.hbs"))
            .expect("Failed to register Traefik Dockerfile template");

        Self { config, handlebars }
    }

    /// Generate Dockerfile for a specific proxy
    pub fn generate_for_proxy(&self, proxy: &ProxyConfig) -> Result<String> {
        match proxy.proxy_type.as_str() {
            "caddy" => self.generate_caddy_dockerfile(proxy),
            "nginx" => self.generate_nginx_dockerfile(proxy),
            "haproxy" => self.generate_haproxy_dockerfile(proxy),
            "traefik" => self.generate_traefik_dockerfile(proxy),
            _ => Err(crate::CerberusError::config(
                format!("Unsupported proxy type for Dockerfile: {}", proxy.proxy_type)
            )),
        }
    }

    /// Generate Caddy Dockerfile
    fn generate_caddy_dockerfile(&self, proxy: &ProxyConfig) -> Result<String> {
        let template_data = json!({
            "proxy": proxy,
            "project_name": &self.config.project.name,
            "services": &self.config.services,
            "has_anubis": self.config.anubis.enabled,
            "base_image": "caddy:2-alpine",
            "config_file": "Caddyfile",
            "config_path": "/etc/caddy/Caddyfile",
            "log_path": "/var/log/caddy",
            "port": proxy.external_port.unwrap_or(proxy.internal_port),
        });

        let dockerfile = self.handlebars.render("caddy_dockerfile", &template_data)?;
        Ok(dockerfile)
    }

    /// Generate Nginx Dockerfile
    fn generate_nginx_dockerfile(&self, proxy: &ProxyConfig) -> Result<String> {
        let template_data = json!({
            "proxy": proxy,
            "project_name": &self.config.project.name,
            "services": &self.config.services,
            "has_anubis": self.config.anubis.enabled,
            "base_image": "nginx:alpine",
            "config_file": "nginx.conf",
            "config_path": "/etc/nginx/nginx.conf",
            "log_path": "/var/log/nginx",
            "port": proxy.external_port.unwrap_or(proxy.internal_port),
        });

        let dockerfile = self.handlebars.render("nginx_dockerfile", &template_data)?;
        Ok(dockerfile)
    }

    /// Generate HAProxy Dockerfile
    fn generate_haproxy_dockerfile(&self, proxy: &ProxyConfig) -> Result<String> {
        let template_data = json!({
            "proxy": proxy,
            "project_name": &self.config.project.name,
            "services": &self.config.services,
            "has_anubis": self.config.anubis.enabled,
            "base_image": "haproxy:alpine",
            "config_file": "haproxy.cfg",
            "config_path": "/usr/local/etc/haproxy/haproxy.cfg",
            "log_path": "/var/log/haproxy",
            "port": proxy.external_port.unwrap_or(proxy.internal_port),
        });

        let dockerfile = self.handlebars.render("haproxy_dockerfile", &template_data)?;
        Ok(dockerfile)
    }

    /// Generate Traefik Dockerfile
    fn generate_traefik_dockerfile(&self, proxy: &ProxyConfig) -> Result<String> {
        let template_data = json!({
            "proxy": proxy,
            "project_name": &self.config.project.name,
            "services": &self.config.services,
            "has_anubis": self.config.anubis.enabled,
            "base_image": "traefik:v3.0",
            "config_file": "traefik.yml",
            "config_path": "/etc/traefik/traefik.yml",
            "log_path": "/var/log/traefik",
            "port": proxy.external_port.unwrap_or(proxy.internal_port),
        });

        let dockerfile = self.handlebars.render("traefik_dockerfile", &template_data)?;
        Ok(dockerfile)
    }

    /// Generate all Dockerfiles for the project
    pub fn generate_all(&self) -> Result<HashMap<String, String>> {
        let mut dockerfiles = HashMap::new();
        
        for proxy in &self.config.proxies {
            let dockerfile = self.generate_for_proxy(proxy)?;
            dockerfiles.insert(proxy.name.clone(), dockerfile);
        }
        
        Ok(dockerfiles)
    }

    /// Generate a multi-stage Dockerfile that includes all proxy configurations
    pub fn generate_multi_stage(&self) -> Result<String> {
        let mut dockerfile = String::new();
        
        // Base stage with common utilities
        dockerfile.push_str(&format!(
            "# Multi-stage Dockerfile for {}\n",
            self.config.project.name
        ));
        dockerfile.push_str("# Generated by Cerberus Rust edition\n\n");
        
        dockerfile.push_str("# Base stage with common tools\n");
        dockerfile.push_str("FROM alpine:latest as base\n");
        dockerfile.push_str("RUN apk add --no-cache \\\n");
        dockerfile.push_str("    curl \\\n");
        dockerfile.push_str("    wget \\\n");
        dockerfile.push_str("    ca-certificates \\\n");
        dockerfile.push_str("    tzdata\n\n");
        
        // Configuration stage
        dockerfile.push_str("# Configuration stage\n");
        dockerfile.push_str("FROM base as config\n");
        dockerfile.push_str("WORKDIR /config\n");
        dockerfile.push_str("COPY built/proxy-configs/ /config/\n");
        dockerfile.push_str("COPY built/anubis/ /config/anubis/\n\n");
        
        // Individual proxy stages
        for proxy in &self.config.proxies {
            dockerfile.push_str(&format!("# {} stage\n", proxy.name));
            
            let base_image = match proxy.proxy_type.as_str() {
                "caddy" => "caddy:2-alpine",
                "nginx" => "nginx:alpine", 
                "haproxy" => "haproxy:alpine",
                "traefik" => "traefik:v3.0",
                _ => "alpine:latest",
            };
            
            dockerfile.push_str(&format!("FROM {} as {}\n", base_image, proxy.name));
            
            let config_path = match proxy.proxy_type.as_str() {
                "caddy" => "/etc/caddy/",
                "nginx" => "/etc/nginx/",
                "haproxy" => "/usr/local/etc/haproxy/",
                "traefik" => "/etc/traefik/",
                _ => "/etc/",
            };
            
            dockerfile.push_str(&format!(
                "COPY --from=config /config/{}/ {}\n",
                proxy.name, config_path
            ));
            if let Some(port) = proxy.external_port {
                dockerfile.push_str(&format!("EXPOSE {}\n", port));
                dockerfile.push_str("HEALTHCHECK --interval=30s --timeout=10s --retries=3 \\\n");
                dockerfile.push_str(&format!(
                    "  CMD curl -f http://localhost:{}/health || exit 1\n",
                    port
                ));
            } else {
                dockerfile.push_str("HEALTHCHECK --interval=30s --timeout=10s --retries=3 \\\n");
                dockerfile.push_str(&format!(
                    "  CMD curl -f http://localhost:{}/health || exit 1\n",
                    proxy.internal_port
                ));
            }
            dockerfile.push_str("\n");
        }
        
        // Final runtime stage
        dockerfile.push_str("# Runtime stage (default)\n");
        if let Some(first_proxy) = self.config.proxies.first() {
            let base_image = match first_proxy.proxy_type.as_str() {
                "caddy" => "caddy:2-alpine",
                "nginx" => "nginx:alpine",
                "haproxy" => "haproxy:alpine", 
                "traefik" => "traefik:v3.0",
                _ => "alpine:latest",
            };
            dockerfile.push_str(&format!("FROM {}\n", base_image));
            dockerfile.push_str(&format!("COPY --from={} / /\n", first_proxy.name));
        } else {
            dockerfile.push_str("FROM alpine:latest\n");
        }
        
        dockerfile.push_str("LABEL maintainer=\"Cerberus\"\n");
        dockerfile.push_str(&format!(
            "LABEL description=\"Multi-proxy container for {}\"\n",
            self.config.project.name
        ));
        dockerfile.push_str("LABEL cerberus.generated=true\n");
        
        Ok(dockerfile)
    }

    /// Generate a development Dockerfile with debugging tools
    pub fn generate_development(&self, proxy: &ProxyConfig) -> Result<String> {
        let mut dockerfile = self.generate_for_proxy(proxy)?;
        
        // Add development tools
        dockerfile.push_str("\n# Development tools\n");
        dockerfile.push_str("RUN apk add --no-cache \\\n");
        dockerfile.push_str("    bash \\\n");
        dockerfile.push_str("    vim \\\n");
        dockerfile.push_str("    htop \\\n");
        dockerfile.push_str("    strace \\\n");
        dockerfile.push_str("    tcpdump \\\n");
        dockerfile.push_str("    bind-tools \\\n");
        dockerfile.push_str("    net-tools\n\n");
        
        dockerfile.push_str("# Enable shell access\n");
        dockerfile.push_str("CMD [\"/bin/bash\"]\n");
        
        Ok(dockerfile)
    }
}
