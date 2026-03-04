use std::fs;
use std::path::PathBuf;

pub struct LocalStore {
    base_dir: PathBuf,
}

impl LocalStore {
    pub fn new() -> Self {
        if let Some(base_dir) = super::runtime_volume_path() {
            return Self { base_dir };
        }

        let xdg = xdg::BaseDirectories::with_prefix(crate::paths::APP_PREFIX);
        let base_dir = xdg
            .get_data_home()
            .map(|d| {
                let volume_dir = d.join("volume");
                let legacy_vault_dir = d.join("vault");
                if volume_dir.exists() || !legacy_vault_dir.exists() {
                    volume_dir
                } else {
                    legacy_vault_dir
                }
            })
            .unwrap_or_else(|| PathBuf::from(".bunnylol-volume"));
        Self { base_dir }
    }
}

impl super::Store for LocalStore {
    fn store_id(&self) -> &str {
        "0"
    }

    fn put(&self, namespace: &str, file_id: &str, content: &[u8]) -> Result<(), super::VaultError> {
        let dir = self.base_dir.join(namespace);
        fs::create_dir_all(&dir)
            .map_err(|e| super::VaultError::Storage(format!("failed to create volume dir: {e}")))?;
        let path = dir.join(file_id);
        fs::write(&path, content)
            .map_err(|e| super::VaultError::Storage(format!("failed to write volume file: {e}")))
    }

    fn get(&self, namespace: &str, file_id: &str) -> Result<Vec<u8>, super::VaultError> {
        let path = self.base_dir.join(namespace).join(file_id);
        fs::read(&path)
            .map_err(|_| super::VaultError::Storage(format!("paste not found: {file_id}")))
    }
}
