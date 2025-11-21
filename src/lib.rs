use ecdsa_spartan2::{
    load_instance, load_proof, load_shared_blinds, load_witness,
    prover::{
        generate_shared_blinds as gen_shared_blinds, prove_circuit, prove_circuit_with_pk,
        reblind, reblind_with_loaded_data, verify_circuit, verify_circuit_with_loaded_data,
    },
    save_keys,
    setup::{
        setup_circuit_keys, setup_circuit_keys_no_save, PREPARE_INSTANCE, PREPARE_PROOF,
        PREPARE_PROVING_KEY, PREPARE_VERIFYING_KEY, PREPARE_WITNESS, SHARED_BLINDS,
        SHOW_INSTANCE, SHOW_PROOF, SHOW_PROVING_KEY, SHOW_VERIFYING_KEY, SHOW_WITNESS,
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
#[cfg_attr(feature = "uniffi", uniffi::record)]
pub struct ProofResult {
    pub prep_ms: u64,
    pub prove_ms: u64,
    pub total_ms: u64,
    pub proof_size_bytes: u64,
    pub comm_w_shared: String,
}

/// Result of a complete benchmark run with timing and size metrics
#[cfg_attr(feature = "uniffi", uniffi::record)]
pub struct BenchmarkResults {
    // Timing metrics (milliseconds)
    pub prepare_setup_ms: u64,
    pub show_setup_ms: u64,
    pub generate_blinds_ms: u64,
    pub prove_prepare_ms: u64,
    pub reblind_prepare_ms: u64,
    pub prove_show_ms: u64,
    pub reblind_show_ms: u64,
    pub verify_prepare_ms: u64,
    pub verify_show_ms: u64,
    // Size metrics (bytes)
    pub prepare_proving_key_bytes: u64,
    pub prepare_verifying_key_bytes: u64,
    pub show_proving_key_bytes: u64,
    pub show_verifying_key_bytes: u64,
    pub prepare_proof_bytes: u64,
    pub show_proof_bytes: u64,
    pub prepare_witness_bytes: u64,
    pub show_witness_bytes: u64,
}

impl BenchmarkResults {
    /// Format bytes into human-readable size string
    pub fn format_size(bytes: u64) -> String {
        if bytes < 1024 {
            format!("{} B", bytes)
        } else if bytes < 1024 * 1024 {
            format!("{:.2} KB", bytes as f64 / 1024.0)
        } else {
            format!("{:.2} MB", bytes as f64 / (1024.0 * 1024.0))
        }
    }
}

/// Errors that can occur during ZK proof operations
#[derive(Debug)]
#[cfg_attr(feature = "uniffi", uniffi::error)]
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
// Benchmark Operations
// ============================================================================

/// Run complete benchmark pipeline for both Prepare and Show circuits
/// Executes all 9 steps: setup, prove, reblind, and verify for both circuits
/// Returns comprehensive timing and size metrics
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn run_complete_benchmark(
    documents_path: String,
    input_path: Option<String>,
) -> Result<BenchmarkResults, ZkProofError> {
    with_working_dir(&documents_path, || {
        // Note: While circuits have 98 shared values (2 keybindings + 96 claim scalars),
        // Hyrax batches all these into a single commitment point.
        // num_shared_rows() returns the number of Hyrax commitment points, not individual scalars.
        const NUM_SHARED: usize = 1;

        // Step 1: Setup Prepare Circuit
        let prepare_circuit = PrepareCircuit::new(input_path.as_ref().map(PathBuf::from));
        let start = std::time::Instant::now();
        let (prepare_pk, prepare_vk) = setup_circuit_keys_no_save(prepare_circuit);
        let prepare_setup_ms = start.elapsed().as_millis() as u64;

        // Save Prepare keys after timing
        save_keys(
            PREPARE_PROVING_KEY,
            PREPARE_VERIFYING_KEY,
            &prepare_pk,
            &prepare_vk,
        )
        .map_err(|e| ZkProofError::IoError {
            message: format!("Failed to save Prepare keys: {}", e),
        })?;

        // Step 2: Setup Show Circuit
        let show_circuit = ShowCircuit::new(input_path.as_ref().map(PathBuf::from));
        let start = std::time::Instant::now();
        let (show_pk, show_vk) = setup_circuit_keys_no_save(show_circuit);
        let show_setup_ms = start.elapsed().as_millis() as u64;

        // Save Show keys after timing
        save_keys(SHOW_PROVING_KEY, SHOW_VERIFYING_KEY, &show_pk, &show_vk).map_err(|e| {
            ZkProofError::IoError {
                message: format!("Failed to save Show keys: {}", e),
            }
        })?;

        // Step 3: Generate Shared Blinds
        let start = std::time::Instant::now();
        gen_shared_blinds::<E>(SHARED_BLINDS, NUM_SHARED);
        let generate_blinds_ms = start.elapsed().as_millis() as u64;

        // Step 4: Prove Prepare Circuit
        let start = std::time::Instant::now();
        let prepare_circuit = PrepareCircuit::new(input_path.as_ref().map(PathBuf::from));
        prove_circuit_with_pk(
            prepare_circuit,
            &prepare_pk,
            PREPARE_INSTANCE,
            PREPARE_WITNESS,
            PREPARE_PROOF,
        );
        let prove_prepare_ms = start.elapsed().as_millis() as u64;

        // Step 5: Reblind Prepare
        // Load data before timing (file I/O should not be part of reblind benchmark)
        let prepare_instance =
            load_instance(PREPARE_INSTANCE).map_err(|e| ZkProofError::FileNotFound {
                message: format!("Failed to load prepare instance: {}", e),
            })?;
        let prepare_witness =
            load_witness(PREPARE_WITNESS).map_err(|e| ZkProofError::FileNotFound {
                message: format!("Failed to load prepare witness: {}", e),
            })?;
        let shared_blinds =
            load_shared_blinds::<E>(SHARED_BLINDS).map_err(|e| ZkProofError::FileNotFound {
                message: format!("Failed to load shared blinds: {}", e),
            })?;

        let start = std::time::Instant::now();
        reblind_with_loaded_data(
            PrepareCircuit::default(),
            &prepare_pk,
            prepare_instance,
            prepare_witness,
            &shared_blinds,
            PREPARE_INSTANCE,
            PREPARE_WITNESS,
            PREPARE_PROOF,
        );
        let reblind_prepare_ms = start.elapsed().as_millis() as u64;

        // Step 6: Prove Show Circuit
        let start = std::time::Instant::now();
        let show_circuit = ShowCircuit::new(input_path.as_ref().map(PathBuf::from));
        prove_circuit_with_pk(
            show_circuit,
            &show_pk,
            SHOW_INSTANCE,
            SHOW_WITNESS,
            SHOW_PROOF,
        );
        let prove_show_ms = start.elapsed().as_millis() as u64;

        // Step 7: Reblind Show
        // Load data before timing (file I/O should not be part of reblind benchmark)
        let show_instance =
            load_instance(SHOW_INSTANCE).map_err(|e| ZkProofError::FileNotFound {
                message: format!("Failed to load show instance: {}", e),
            })?;
        let show_witness = load_witness(SHOW_WITNESS).map_err(|e| ZkProofError::FileNotFound {
            message: format!("Failed to load show witness: {}", e),
        })?;
        // Reuse shared_blinds from Prepare step (already loaded)

        let start = std::time::Instant::now();
        reblind_with_loaded_data(
            ShowCircuit::default(),
            &show_pk,
            show_instance,
            show_witness,
            &shared_blinds,
            SHOW_INSTANCE,
            SHOW_WITNESS,
            SHOW_PROOF,
        );
        let reblind_show_ms = start.elapsed().as_millis() as u64;

        // Step 8: Verify Prepare
        // Load proof before timing (file I/O should not be part of verify benchmark)
        let prepare_proof =
            load_proof(PREPARE_PROOF).map_err(|e| ZkProofError::FileNotFound {
                message: format!("Failed to load prepare proof: {}", e),
            })?;

        let start = std::time::Instant::now();
        verify_circuit_with_loaded_data(&prepare_proof, &prepare_vk);
        let verify_prepare_ms = start.elapsed().as_millis() as u64;

        // Step 9: Verify Show
        // Load proof before timing (file I/O should not be part of verify benchmark)
        let show_proof = load_proof(SHOW_PROOF).map_err(|e| ZkProofError::FileNotFound {
            message: format!("Failed to load show proof: {}", e),
        })?;

        let start = std::time::Instant::now();
        verify_circuit_with_loaded_data(&show_proof, &show_vk);
        let verify_show_ms = start.elapsed().as_millis() as u64;

        // Measure file sizes
        let prepare_proving_key_bytes = get_proof_size(PREPARE_PROVING_KEY)?;
        let prepare_verifying_key_bytes = get_proof_size(PREPARE_VERIFYING_KEY)?;
        let show_proving_key_bytes = get_proof_size(SHOW_PROVING_KEY)?;
        let show_verifying_key_bytes = get_proof_size(SHOW_VERIFYING_KEY)?;
        let prepare_proof_bytes = get_proof_size(PREPARE_PROOF)?;
        let show_proof_bytes = get_proof_size(SHOW_PROOF)?;
        let prepare_witness_bytes = get_proof_size(PREPARE_WITNESS)?;
        let show_witness_bytes = get_proof_size(SHOW_WITNESS)?;

        Ok(BenchmarkResults {
            prepare_setup_ms,
            show_setup_ms,
            generate_blinds_ms,
            prove_prepare_ms,
            reblind_prepare_ms,
            prove_show_ms,
            reblind_show_ms,
            verify_prepare_ms,
            verify_show_ms,
            prepare_proving_key_bytes,
            prepare_verifying_key_bytes,
            show_proving_key_bytes,
            show_verifying_key_bytes,
            prepare_proof_bytes,
            show_proof_bytes,
            prepare_witness_bytes,
            show_witness_bytes,
        })
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
