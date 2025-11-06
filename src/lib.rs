use ecdsa_spartan2::{
    setup_circuit_keys, run_circuit, prove_circuit,
    PrepareCircuit, ShowCircuit,
    PREPARE_PROVING_KEY, PREPARE_VERIFYING_KEY,
    SHOW_PROVING_KEY, SHOW_VERIFYING_KEY,
};

// Initializes the shared UniFFI scaffolding and defines the `MoproError` enum.
mopro_ffi::app!();

/// You can also customize the bindings by #[uniffi::export]
/// Reference: https://mozilla.github.io/uniffi-rs/latest/proc_macro/index.html
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn mopro_hello_world() -> String {
    "Hello, World!".to_string()
}

/// Setup JWT circuit keys (Prepare circuit)
/// Generates proving and verifying keys for the Prepare circuit
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn setup_prepare_keys(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let start = std::time::Instant::now();
    setup_circuit_keys(PrepareCircuit, PREPARE_PROVING_KEY, PREPARE_VERIFYING_KEY);
    let elapsed_ms = start.elapsed().as_millis();

    let _ = std::env::set_current_dir(original_dir);

    format!("Prepare circuit keys setup completed in {}ms", elapsed_ms)
}

/// Setup Show circuit keys
/// Generates proving and verifying keys for the Show circuit
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn setup_show_keys(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let start = std::time::Instant::now();
    setup_circuit_keys(ShowCircuit, SHOW_PROVING_KEY, SHOW_VERIFYING_KEY);
    let elapsed_ms = start.elapsed().as_millis();

    let _ = std::env::set_current_dir(original_dir);

    format!("Show circuit keys setup completed in {}ms", elapsed_ms)
}

/// Run full Prepare circuit workflow (setup + prove + verify)
/// Performs complete JWT circuit execution with all phases
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn run_prepare_circuit(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let result = std::panic::catch_unwind(|| {
        run_circuit(PrepareCircuit);
    });

    let _ = std::env::set_current_dir(original_dir);

    match result {
        Ok(_) => "Prepare circuit completed successfully (check logs for timing details)".to_string(),
        Err(_) => "Prepare circuit failed".to_string(),
    }
}

/// Run full Show circuit workflow (setup + prove + verify)
/// Performs complete Show circuit execution with all phases
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn run_show_circuit(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let result = std::panic::catch_unwind(|| {
        run_circuit(ShowCircuit);
    });

    let _ = std::env::set_current_dir(original_dir);

    match result {
        Ok(_) => "Show circuit completed successfully (check logs for timing details)".to_string(),
        Err(_) => "Show circuit failed".to_string(),
    }
}

/// Prove with Prepare circuit using existing keys
/// Runs prep_prove + prove phases only (assumes keys exist)
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn prove_prepare_circuit(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let result = std::panic::catch_unwind(|| {
        prove_circuit(PrepareCircuit, PREPARE_PROVING_KEY);
    });

    let _ = std::env::set_current_dir(original_dir);

    match result {
        Ok(_) => "Prepare circuit proof completed successfully (check logs for timing details)".to_string(),
        Err(_) => "Prepare circuit proof failed".to_string(),
    }
}

/// Prove with Show circuit using existing keys
/// Runs prep_prove + prove phases only (assumes keys exist)
#[cfg_attr(feature = "uniffi", uniffi::export)]
pub fn prove_show_circuit(documents_path: String) -> String {
    let original_dir = std::env::current_dir().unwrap_or_default();

    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }

    let result = std::panic::catch_unwind(|| {
        prove_circuit(ShowCircuit, SHOW_PROVING_KEY);
    });

    let _ = std::env::set_current_dir(original_dir);

    match result {
        Ok(_) => "Show circuit proof completed successfully (check logs for timing details)".to_string(),
        Err(_) => "Show circuit proof failed".to_string(),
    }
}

#[cfg(test)]
mod uniffi_tests {
    use super::*;

    #[test]
    fn test_mopro_hello_world() {
        assert_eq!(mopro_hello_world(), "Hello, World!");
    }

    /// Test setup_prepare_keys with directory handling
    /// Note: This test verifies directory restoration logic
    #[test]
    fn test_setup_prepare_keys_directory_handling() {
        let original_dir = std::env::current_dir().unwrap();

        // Test with nonexistent path - should return error and restore directory
        let result = setup_prepare_keys("/nonexistent/test/path".to_string());
        assert!(result.starts_with("Failed to set working directory:"));

        // Verify directory was restored
        let after_dir = std::env::current_dir().unwrap();
        assert_eq!(original_dir, after_dir);
    }

    /// Test setup_show_keys with directory handling
    /// Note: This test verifies directory restoration logic
    #[test]
    fn test_setup_show_keys_directory_handling() {
        let original_dir = std::env::current_dir().unwrap();

        // Test with nonexistent path - should return error and restore directory
        let result = setup_show_keys("/nonexistent/test/path".to_string());
        assert!(result.starts_with("Failed to set working directory:"));

        // Verify directory was restored
        let after_dir = std::env::current_dir().unwrap();
        assert_eq!(original_dir, after_dir);
    }
}
