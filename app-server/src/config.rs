/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Configuration for bunnylol CLI
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BunnylolConfig {
    /// Browser to open URLs in (optional)
    /// Examples: "firefox", "chrome", "chromium", "safari"
    #[serde(default)]
    pub browser: Option<String>,

    /// Default search engine when command not recognized (optional)
    /// Options: "google" (default), "ddg", "bing"
    #[serde(default = "default_search_engine")]
    pub default_search: String,

    /// Custom command aliases
    #[serde(default)]
    pub aliases: HashMap<String, String>,

    /// Command history settings
    #[serde(default)]
    pub history: HistoryConfig,

    /// Server configuration (for bunnylol serve)
    #[serde(default)]
    pub server: ServerConfig,
}

impl Default for BunnylolConfig {
    fn default() -> Self {
        Self {
            browser: None,
            default_search: default_search_engine(),
            aliases: HashMap::new(),
            history: HistoryConfig::default(),
            server: ServerConfig::default(),
        }
    }
}

/// Configuration for command history
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryConfig {
    /// Whether history tracking is enabled
    #[serde(default = "default_history_enabled")]
    pub enabled: bool,

    /// Maximum number of history entries to keep
    #[serde(default = "default_max_entries")]
    pub max_entries: usize,
}

impl Default for HistoryConfig {
    fn default() -> Self {
        Self {
            enabled: default_history_enabled(),
            max_entries: default_max_entries(),
        }
    }
}

/// Configuration for bunnylol server
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Port to bind the server to
    #[serde(default = "default_port")]
    pub port: u16,

    /// Address to bind to (127.0.0.1 for localhost, 0.0.0.0 for network)
    #[serde(default = "default_address")]
    pub address: String,

    /// Rocket log level (normal, debug, critical, off)
    #[serde(default = "default_log_level")]
    pub log_level: String,

    /// Filesystem path for shared volume storage.
    ///
    /// If set, blob storage uses this directory instead of the default local data dir.
    /// This is intended for shared synced folders (e.g. Google Drive mount paths).
    #[serde(default)]
    pub volume_path: Option<String>,
}

impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            port: default_port(),
            address: default_address(),
            log_level: default_log_level(),
            volume_path: None,
        }
    }
}

impl ServerConfig {
    /// Get the local URL for the server.
    ///
    /// Lolabunny always serves and consumes links through localhost.
    pub fn get_display_url(&self) -> String {
        format!("http://localhost:{}", self.port)
    }
}

fn default_search_engine() -> String {
    "google".to_string()
}

fn default_history_enabled() -> bool {
    true
}

fn default_max_entries() -> usize {
    1000
}

fn default_port() -> u16 {
    8085
}

fn default_address() -> String {
    "127.0.0.1".to_string()
}

fn default_log_level() -> String {
    "normal".to_string()
}

impl BunnylolConfig {
    /// Resolve a command, checking aliases first
    /// Returns the resolved command (either from alias or original)
    pub fn resolve_command(&self, command: &str) -> String {
        self.aliases
            .get(command)
            .cloned()
            .unwrap_or_else(|| command.to_string())
    }

    /// Get the search engine URL for a query
    pub fn get_search_url(&self, query: &str) -> String {
        let encoded_query =
            percent_encoding::utf8_percent_encode(query, percent_encoding::NON_ALPHANUMERIC)
                .to_string();

        match self.default_search.as_str() {
            "ddg" | "duckduckgo" => format!("https://duckduckgo.com/?q={}", encoded_query),
            "bing" => format!("https://www.bing.com/search?q={}", encoded_query),
            _ => format!("https://www.google.com/search?q={}", encoded_query), // Default to Google
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = BunnylolConfig::default();
        assert_eq!(config.browser, None);
        assert_eq!(config.default_search, "google");
        assert!(config.aliases.is_empty());
        assert!(config.history.enabled);
        assert_eq!(config.history.max_entries, 1000);
        assert_eq!(config.server.port, 8085);
        assert_eq!(config.server.address, "127.0.0.1");
        assert_eq!(config.server.log_level, "normal");
        assert_eq!(config.server.volume_path, None);
    }

    #[test]
    fn test_resolve_command_with_alias() {
        let mut config = BunnylolConfig::default();
        config
            .aliases
            .insert("work".to_string(), "gh mycompany".to_string());

        assert_eq!(config.resolve_command("work"), "gh mycompany");
        assert_eq!(config.resolve_command("ig"), "ig"); // No alias
    }

    #[test]
    fn test_get_search_url_google() {
        let config = BunnylolConfig::default();
        let url = config.get_search_url("hello world");
        assert!(url.starts_with("https://www.google.com/search?q="));
        assert!(url.contains("hello"));
        assert!(url.contains("world"));
    }

    #[test]
    fn test_get_search_url_ddg() {
        let mut config = BunnylolConfig::default();
        config.default_search = "ddg".to_string();
        let url = config.get_search_url("test query");
        assert!(url.starts_with("https://duckduckgo.com/?q="));
    }

    #[test]
    fn test_get_search_url_bing() {
        let mut config = BunnylolConfig::default();
        config.default_search = "bing".to_string();
        let url = config.get_search_url("test query");
        assert!(url.starts_with("https://www.bing.com/search?q="));
    }

    #[test]
    fn test_server_config_defaults() {
        let config = ServerConfig::default();
        assert_eq!(config.port, 8085);
        assert_eq!(config.address, "127.0.0.1");
        assert_eq!(config.log_level, "normal");
        assert_eq!(config.volume_path, None);
    }

    #[test]
    fn test_parse_valid_toml() {
        let toml_str = r#"
            browser = "firefox"
            default_search = "ddg"

            [aliases]
            work = "gh mycompany"
            blog = "gh username/blog"

            [history]
            enabled = false
            max_entries = 500

            [server]
            port = 9000
            address = "0.0.0.0"
            log_level = "debug"
            volume_path = "/tmp/lolabunny-volume"
        "#;

        let config: BunnylolConfig = toml::from_str(toml_str).unwrap();
        assert_eq!(config.browser, Some("firefox".to_string()));
        assert_eq!(config.default_search, "ddg");
        assert_eq!(
            config.aliases.get("work"),
            Some(&"gh mycompany".to_string())
        );
        assert_eq!(
            config.aliases.get("blog"),
            Some(&"gh username/blog".to_string())
        );
        assert!(!config.history.enabled);
        assert_eq!(config.history.max_entries, 500);
        assert_eq!(config.server.port, 9000);
        assert_eq!(config.server.address, "0.0.0.0");
        assert_eq!(config.server.log_level, "debug");
        assert_eq!(
            config.server.volume_path,
            Some("/tmp/lolabunny-volume".to_string())
        );
    }

    #[test]
    fn test_get_display_url_localhost() {
        let config = ServerConfig::default();
        assert_eq!(config.get_display_url(), "http://localhost:8085");

        let mut config2 = ServerConfig::default();
        config2.port = 9000;
        assert_eq!(config2.get_display_url(), "http://localhost:9000");
    }
}
