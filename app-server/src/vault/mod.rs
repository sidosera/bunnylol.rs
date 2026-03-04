mod crypto;
mod local;
pub mod secrets;

use std::fmt;
use std::path::PathBuf;
use std::sync::{OnceLock, RwLock};

trait Store {
    fn store_id(&self) -> &str;
    fn put(&self, namespace: &str, file_id: &str, content: &[u8]) -> Result<(), VaultError>;
    fn get(&self, namespace: &str, file_id: &str) -> Result<Vec<u8>, VaultError>;
}

const STORE_ID_LEN: usize = 1;
static RUNTIME_VOLUME_PATH: OnceLock<RwLock<Option<PathBuf>>> = OnceLock::new();

#[derive(Debug)]
pub enum VaultError {
    VolumePathLock,
    InvalidBlobId(String),
    UnknownStoreId(String),
    Storage(String),
    Crypto(String),
}

impl fmt::Display for VaultError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::VolumePathLock => write!(f, "failed to acquire volume path lock"),
            Self::InvalidBlobId(id) => write!(f, "invalid blob ID: {id}"),
            Self::UnknownStoreId(id) => write!(f, "unknown store ID: '{id}'"),
            Self::Storage(msg) => write!(f, "{msg}"),
            Self::Crypto(msg) => write!(f, "{msg}"),
        }
    }
}

impl std::error::Error for VaultError {}

fn runtime_volume_path_cell() -> &'static RwLock<Option<PathBuf>> {
    RUNTIME_VOLUME_PATH.get_or_init(|| RwLock::new(None))
}

pub fn configure_volume_path(path: Option<&str>) -> Result<(), VaultError> {
    let normalized = path.and_then(|p| {
        let trimmed = p.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(PathBuf::from(trimmed))
        }
    });

    let mut guard = runtime_volume_path_cell()
        .write()
        .map_err(|_| VaultError::VolumePathLock)?;
    *guard = normalized;
    Ok(())
}

pub(super) fn runtime_volume_path() -> Option<PathBuf> {
    runtime_volume_path_cell()
        .read()
        .ok()
        .and_then(|g| g.clone())
}

fn store_for_id(store_id: &str) -> Result<Box<dyn Store>, VaultError> {
    match store_id {
        "0" => Ok(Box::new(local::LocalStore::new())),
        other => Err(VaultError::UnknownStoreId(other.to_string())),
    }
}

pub struct Vault {
    backend: Box<dyn Store>,
}

impl Vault {
    pub fn from_config() -> Result<Self, VaultError> {
        // Runtime configuration is provided by process arguments and configured
        // via `configure_volume_path` at server launch.
        Ok(Self {
            backend: Box::new(local::LocalStore::new()),
        })
    }

    /// Encrypt and store content. Returns a blob ID with embedded store ID.
    pub fn put(&self, namespace: &str, content: &[u8]) -> Result<String, VaultError> {
        let raw_id = crypto::generate_id();
        let encrypted = crypto::encrypt(&raw_id, content).map_err(VaultError::Crypto)?;
        let fid = crypto::file_id(&raw_id);
        self.backend.put(namespace, &fid, &encrypted)?;
        Ok(format!("{}{raw_id}", self.backend.store_id()))
    }

    /// Fetch and decrypt content by blob ID (store ID + crypto ID).
    pub fn get(namespace: &str, blob_id: &str) -> Result<Vec<u8>, VaultError> {
        if blob_id.len() <= STORE_ID_LEN {
            return Err(VaultError::InvalidBlobId(blob_id.to_string()));
        }
        let store_id = &blob_id[..STORE_ID_LEN];
        let raw_id = &blob_id[STORE_ID_LEN..];
        let backend = store_for_id(store_id)?;
        let fid = crypto::file_id(raw_id);
        let encrypted = backend.get(namespace, &fid)?;
        crypto::decrypt(raw_id, &encrypted).map_err(VaultError::Crypto)
    }
}
