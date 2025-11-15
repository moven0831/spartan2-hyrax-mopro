use ecdsa_spartan2::{
    prover::{prove_circuit, reblind, verify_circuit},
    setup::{
        setup_circuit_keys, PREPARE_INSTANCE, PREPARE_PROOF, PREPARE_PROVING_KEY,
        PREPARE_VERIFYING_KEY, PREPARE_WITNESS, SHARED_BLINDS, SHOW_INSTANCE, SHOW_PROOF,
        SHOW_PROVING_KEY, SHOW_VERIFYING_KEY, SHOW_WITNESS,
    },
    PrepareCircuit, ShowCircuit, E,
};
use std::path::PathBuf;

// Initializes the shared UniFFI scaffolding and defines the `MoproError` enum.
mopro_ffi::app!();

// ============================================================================
// Core Types
// ============================================================================

/// Result of a proving operation with timing and proof metadata
pub struct ProofResult {
    pub prep_ms: u64,
    pub prove_ms: u64,
    pub total_ms: u64,
    pub proof_size_bytes: u64,
    pub comm_w_shared: String,
}

/// Errors that can occur during ZK proof operations
#[derive(Debug)]
pub enum ZkProofError {
    FileNotFound { message: String },
    ProofGenerationFailed { message: String },
    VerificationFailed { message: String },
    InvalidInput { message: String },
    SetupRequired { message: String },
    IoError { message: String },
}

impl std::fmt::Display for ZkProofError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ZkProofError::FileNotFound { message } => write!(f, "File not found: {}", message),
            ZkProofError::ProofGenerationFailed { message } => {
                write!(f, "Proof generation failed: {}", message)
            }
            ZkProofError::VerificationFailed { message } => {
                write!(f, "Verification failed: {}", message)
            }
            ZkProofError::InvalidInput { message } => write!(f, "Invalid input: {}", message),
            ZkProofError::SetupRequired { message } => write!(f, "Setup required: {}", message),
            ZkProofError::IoError { message } => write!(f, "IO error: {}", message),
        }
    }
}

impl std::error::Error for ZkProofError {}

impl From<std::io::Error> for ZkProofError {
    fn from(e: std::io::Error) -> Self {
        ZkProofError::IoError {
            message: e.to_string(),
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Safely execute a function with a changed working directory
fn with_working_dir<F, T>(path: &str, f: F) -> Result<T, ZkProofError>
where
    F: FnOnce() -> Result<T, ZkProofError>,
{
    let original_dir = std::env::current_dir()?;

    std::env::set_current_dir(path).map_err(|e| ZkProofError::IoError {
        message: format!("Failed to set working directory to '{}': {}", path, e),
    })?;

    let result = f();

    // Always restore original directory, even on error
    let _ = std::env::set_current_dir(original_dir);

    result
}

// ============================================================================
// Setup Operations
// ============================================================================

/// Setup Prepare (JWT) circuit keys
/// Generates proving and verifying keys for the Prepare circuit
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn setup_prepare_keys(
    documents_path: String,
    input_path: Option<String>,
) -> Result<String, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = PrepareCircuit::new(input_path.map(PathBuf::from));

        let start = std::time::Instant::now();
        setup_circuit_keys(circuit, PREPARE_PROVING_KEY, PREPARE_VERIFYING_KEY);
        let elapsed_ms = start.elapsed().as_millis();

        Ok(format!(
            "Prepare circuit keys setup completed in {}ms",
            elapsed_ms
        ))
    })
}

/// Setup Show circuit keys
/// Generates proving and verifying keys for the Show circuit
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn setup_show_keys(
    documents_path: String,
    input_path: Option<String>,
) -> Result<String, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = ShowCircuit::new(input_path.map(PathBuf::from));

        let start = std::time::Instant::now();
        setup_circuit_keys(circuit, SHOW_PROVING_KEY, SHOW_VERIFYING_KEY);
        let elapsed_ms = start.elapsed().as_millis();

        Ok(format!(
            "Show circuit keys setup completed in {}ms",
            elapsed_ms
        ))
    })
}

// ============================================================================
// Shared Blinds Generation
// ============================================================================

/// Generate shared blinding factors for both circuits
/// Creates random blinding factors that enable proof reblinding
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn generate_shared_blinds(documents_path: String) -> Result<String, ZkProofError> {
    with_working_dir(&documents_path, || {
        use ecdsa_spartan2::prover::generate_shared_blinds as gen_blinds;

        // Note: While circuits have 98 shared values (2 keybindings + 96 claim scalars),
        // Hyrax batches all these into a single commitment point.
        // num_shared_rows() returns the number of Hyrax commitment points, not individual scalars.
        const NUM_SHARED: usize = 1;
        gen_blinds::<E>(SHARED_BLINDS, NUM_SHARED);

        Ok("Shared blinds generated successfully".to_string())
    })
}

// ============================================================================
// Prove Operations
// ============================================================================

/// Generate Prepare (JWT) circuit proof
/// Runs prep_prove + prove phases using existing keys
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn prove_prepare(
    documents_path: String,
    input_path: Option<String>,
) -> Result<ProofResult, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = PrepareCircuit::new(input_path.map(PathBuf::from));

        let start = std::time::Instant::now();
        prove_circuit(
            circuit,
            PREPARE_PROVING_KEY,
            PREPARE_INSTANCE,
            PREPARE_WITNESS,
            PREPARE_PROOF,
        );
        let total_ms = start.elapsed().as_millis() as u64;

        // Get proof size and comm_W_shared
        let proof_size_bytes = get_proof_size(PREPARE_PROOF)?;
        let comm_w_shared = extract_comm_w_shared(PREPARE_INSTANCE)?;

        Ok(ProofResult {
            prep_ms: 0, // prover doesn't separate timing
            prove_ms: total_ms,
            total_ms,
            proof_size_bytes,
            comm_w_shared,
        })
    })
}

/// Generate Show circuit proof
/// Runs prep_prove + prove phases using existing keys
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn prove_show(
    documents_path: String,
    input_path: Option<String>,
) -> Result<ProofResult, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = ShowCircuit::new(input_path.map(PathBuf::from));

        let start = std::time::Instant::now();
        prove_circuit(
            circuit,
            SHOW_PROVING_KEY,
            SHOW_INSTANCE,
            SHOW_WITNESS,
            SHOW_PROOF,
        );
        let total_ms = start.elapsed().as_millis() as u64;

        // Get proof size and comm_W_shared
        let proof_size_bytes = get_proof_size(SHOW_PROOF)?;
        let comm_w_shared = extract_comm_w_shared(SHOW_INSTANCE)?;

        Ok(ProofResult {
            prep_ms: 0,
            prove_ms: total_ms,
            total_ms,
            proof_size_bytes,
            comm_w_shared,
        })
    })
}

// ============================================================================
// Reblind Operations
// ============================================================================

/// Reblind Prepare circuit proof
/// Generates a new unlinkable proof while preserving comm_W_shared
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn reblind_prepare(documents_path: String) -> Result<ProofResult, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = PrepareCircuit::new(None);

        let start = std::time::Instant::now();
        reblind(
            circuit,
            PREPARE_PROVING_KEY,
            PREPARE_INSTANCE,
            PREPARE_WITNESS,
            PREPARE_PROOF,
            SHARED_BLINDS,
        );
        let elapsed_ms = start.elapsed().as_millis() as u64;

        // Get proof size and comm_W_shared
        let proof_size_bytes = get_proof_size(PREPARE_PROOF)?;
        let comm_w_shared = extract_comm_w_shared(PREPARE_INSTANCE)?;

        Ok(ProofResult {
            prep_ms: 0,
            prove_ms: elapsed_ms,
            total_ms: elapsed_ms,
            proof_size_bytes,
            comm_w_shared,
        })
    })
}

/// Reblind Show circuit proof
/// Generates a new unlinkable proof while preserving comm_W_shared
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn reblind_show(documents_path: String) -> Result<ProofResult, ZkProofError> {
    with_working_dir(&documents_path, || {
        let circuit = ShowCircuit::new(None);

        let start = std::time::Instant::now();
        reblind(
            circuit,
            SHOW_PROVING_KEY,
            SHOW_INSTANCE,
            SHOW_WITNESS,
            SHOW_PROOF,
            SHARED_BLINDS,
        );
        let elapsed_ms = start.elapsed().as_millis() as u64;

        // Get proof size and comm_W_shared
        let proof_size_bytes = get_proof_size(SHOW_PROOF)?;
        let comm_w_shared = extract_comm_w_shared(SHOW_INSTANCE)?;

        Ok(ProofResult {
            prep_ms: 0,
            prove_ms: elapsed_ms,
            total_ms: elapsed_ms,
            proof_size_bytes,
            comm_w_shared,
        })
    })
}

// ============================================================================
// Verify Operations
// ============================================================================

/// Verify Prepare circuit proof
/// Verifies the proof using the verifying key
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn verify_prepare(documents_path: String) -> Result<bool, ZkProofError> {
    with_working_dir(&documents_path, || {
        verify_circuit(PREPARE_PROOF, PREPARE_VERIFYING_KEY);
        Ok(true)
    })
}

/// Verify Show circuit proof
/// Verifies the proof using the verifying key
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn verify_show(documents_path: String) -> Result<bool, ZkProofError> {
    with_working_dir(&documents_path, || {
        verify_circuit(SHOW_PROOF, SHOW_VERIFYING_KEY);
        Ok(true)
    })
}

// ============================================================================
// Inspection Operations
// ============================================================================

/// Get the shared witness commitment for a circuit
/// Returns hex-encoded commitment that links Prepare and Show proofs
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn get_comm_w_shared(
    documents_path: String,
    circuit_type: String,
) -> Result<String, ZkProofError> {
    with_working_dir(&documents_path, || {
        let instance_path = match circuit_type.as_str() {
            "prepare" => PREPARE_INSTANCE,
            "show" => SHOW_INSTANCE,
            _ => {
                return Err(ZkProofError::InvalidInput {
                    message: format!(
                        "Invalid circuit_type '{}'. Must be 'prepare' or 'show'",
                        circuit_type
                    ),
                })
            }
        };

        extract_comm_w_shared(instance_path)
    })
}

// ============================================================================
// Internal Helper Functions
// ============================================================================

/// Extract comm_W_shared from a saved instance file
fn extract_comm_w_shared(instance_path: &str) -> Result<String, ZkProofError> {
    use ecdsa_spartan2::setup::load_instance;

    let instance = load_instance(instance_path).map_err(|e| ZkProofError::FileNotFound {
        message: format!("Failed to load instance from '{}': {}", instance_path, e),
    })?;

    // Convert comm_W_shared to hex string
    let comm_w_shared_hex = format!("{:?}", instance.comm_W_shared);
    Ok(comm_w_shared_hex)
}

/// Get the size of a proof file in bytes
fn get_proof_size(proof_path: &str) -> Result<u64, ZkProofError> {
    let metadata = std::fs::metadata(proof_path).map_err(|e| ZkProofError::FileNotFound {
        message: format!("Failed to get proof size from '{}': {}", proof_path, e),
    })?;

    Ok(metadata.len())
}

// ============================================================================
// Legacy Test Function
// ============================================================================

/// Test function for basic UniFFI integration
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn mopro_hello_world() -> String {
    "Hello, World!".to_string()
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    use std::path::Path;

    #[test]
    fn test_mopro_hello_world() {
        assert_eq!(mopro_hello_world(), "Hello, World!");
    }

    #[test]
    fn test_with_working_dir_error_handling() {
        let original_dir = std::env::current_dir().unwrap();

        // Test with nonexistent path - should return error and restore directory
        let result = with_working_dir("/nonexistent/test/path", || {
            Ok::<_, ZkProofError>("should not reach here".to_string())
        });

        assert!(result.is_err());

        // Verify directory was restored
        let after_dir = std::env::current_dir().unwrap();
        assert_eq!(original_dir, after_dir);
    }

    #[test]
    fn test_invalid_circuit_type() {
        let result = get_comm_w_shared(".".to_string(), "invalid".to_string());
        assert!(matches!(result, Err(ZkProofError::InvalidInput { .. })));
    }
}
