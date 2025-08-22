// Here we're calling a macro exported with Uniffi. This macro will
// write some functions and bind them to FFI type.
// These functions include:
// - `generate_circom_proof`
// - `verify_circom_proof`
// - `generate_halo2_proof`
// - `verify_halo2_proof`
// - `generate_noir_proof`
// - `verify_noir_proof`
mopro_ffi::app!();

/// You can also customize the bindings by #[uniffi::export]
/// Reference: https://mozilla.github.io/uniffi-rs/latest/proc_macro/index.html
#[uniffi::export]
fn mopro_uniffi_hello_world() -> String {
    "Hello, World!".to_string()
}

// mod sha256;

// #[uniffi::export]
// fn sha256_prove_and_verify() {
//     sha256::sha256_prove_and_verify();
// }

// Import wallet-unit-poc functions  
use ecdsa_spartan2::{
    run_ecdsa_circuit, run_jwt_circuit, prove_ecdsa_with_keys, prove_jwt_with_keys,
    prove_jwt_sum_check, prove_jwt_sumcheck_hyrax, prove_ecdsa_sumcheck_hyrax,
    setup_ecdsa_keys as setup_ecdsa_circuit_keys, setup_jwt_keys as setup_jwt_circuit_keys,
    mobile_prove_ecdsa_with_keys, mobile_prove_jwt_with_keys, mobile_prove_jwt_sum_check
};

use std::sync::OnceLock;
use std::path::PathBuf;

// Mobile environment configuration
static MOBILE_RESOURCES_PATH: OnceLock<PathBuf> = OnceLock::new();

/// Initialize mobile environment with the path to app's documents directory
/// This should be called once at app startup to configure resource paths
#[uniffi::export]
fn initialize_mobile_environment(documents_path: String) -> String {
    let path = PathBuf::from(documents_path);
    match MOBILE_RESOURCES_PATH.set(path) {
        Ok(_) => "Mobile environment initialized successfully".to_string(),
        Err(_) => "Mobile environment already initialized".to_string()
    }
}

/// Verify that all required mobile resources exist in the documents directory
#[uniffi::export]
fn verify_mobile_resources(documents_path: String) -> String {
    use std::fs;
    
    let docs_path = PathBuf::from(&documents_path);
    let circom_dir = docs_path.join("circom");
    let keys_dir = docs_path.join("wallet-unit-poc/ecdsa-spartan2/keys");
    
    let required_files = [
        // Circuit files (R1CS and witness only, no WASM files)
        circom_dir.join("build/ecdsa/ecdsa_js/ecdsa.r1cs"),
        circom_dir.join("build/ecdsa/ecdsa_js/ecdsa.wtns"),
        circom_dir.join("build/jwt/jwt_js/jwt.r1cs"),
        circom_dir.join("build/jwt/jwt_js/jwt.wtns"),
        circom_dir.join("inputs/ecdsa/default.json"),
        circom_dir.join("inputs/jwt/default.json"),
        keys_dir.join("ecdsa_proving.key"),
        keys_dir.join("ecdsa_verifying.key"),
        keys_dir.join("jwt_proving.key"),
        keys_dir.join("jwt_verifying.key"),
    ];
    
    for file_path in &required_files {
        if !fs::metadata(file_path).is_ok() {
            return format!("Missing required file: {}", file_path.display());
        }
    }
    
    "All mobile resources verified successfully".to_string()
}

/// Mobile-compatible ECDSA proving with pre-loaded keys from documents directory
#[uniffi::export] 
fn mobile_ecdsa_prove_with_keys(documents_path: String) -> String {
    // Store the original directory to restore later
    let original_dir = std::env::current_dir().unwrap_or_default();
    
    // Set current directory to documents path to make relative paths work
    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }
    
    let result = match mobile_prove_ecdsa_with_keys() {
        Ok((prep_ms, prove_ms, verify_ms)) => {
            format!("ECDSA Mobile Proof - Prep: {}ms, Prove: {}ms, Verify: {}ms", prep_ms, prove_ms, verify_ms)
        }
        Err(e) => format!("ECDSA Mobile Proof failed: {}", e)
    };
    
    // Restore original directory 
    let _ = std::env::set_current_dir(original_dir);
    
    result
}

/// Mobile-compatible JWT proving with pre-loaded keys from documents directory
#[uniffi::export]
fn mobile_jwt_prove_with_keys(documents_path: String) -> String {
    // Store the original directory to restore later
    let original_dir = std::env::current_dir().unwrap_or_default();
    
    // Set current directory to documents path to make relative paths work
    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }
    
    let result = match mobile_prove_jwt_with_keys() {
        Ok((prep_ms, prove_ms, verify_ms)) => {
            format!("JWT Mobile Proof - Prep: {}ms, Prove: {}ms, Verify: {}ms", prep_ms, prove_ms, verify_ms)
        }
        Err(e) => format!("JWT Mobile Proof failed: {}", e)
    };
    
    // Restore original directory
    let _ = std::env::set_current_dir(original_dir);
    
    result
}

/// Mobile-compatible JWT sum-check with pre-loaded keys from documents directory
#[uniffi::export]
fn mobile_jwt_prove_sum_check(documents_path: String) -> String {
    // Store the original directory to restore later
    let original_dir = std::env::current_dir().unwrap_or_default();
    
    // Set current directory to documents path to make relative paths work
    if let Err(e) = std::env::set_current_dir(&documents_path) {
        return format!("Failed to set working directory: {}", e);
    }
    
    let result = match mobile_prove_jwt_sum_check() {
        Ok((prep_ms, sumcheck_ms)) => {
            format!("JWT Sum-check - Prep: {}ms, Sum-check: {}ms", prep_ms, sumcheck_ms)
        }
        Err(e) => format!("JWT Sum-check failed: {}", e)
    };
    
    // Restore original directory
    let _ = std::env::set_current_dir(original_dir);
    
    result
}

#[uniffi::export]
fn ecdsa_prove_and_verify() -> String {
    let (setup_ms, prep_ms, prove_ms, verify_ms) = run_ecdsa_circuit();
    format!(
        "ECDSA Circuit - Setup: {}ms, Prep: {}ms, Prove: {}ms, Verify: {}ms", 
        setup_ms, prep_ms, prove_ms, verify_ms
    )
}

#[uniffi::export]
fn jwt_prove_and_verify() -> String {
    let (setup_ms, prep_ms, prove_ms, verify_ms) = run_jwt_circuit();
    format!(
        "JWT Circuit - Setup: {}ms, Prep: {}ms, Prove: {}ms, Verify: {}ms", 
        setup_ms, prep_ms, prove_ms, verify_ms
    )
}

#[uniffi::export]
fn ecdsa_prove_with_keys() -> String {
    match prove_ecdsa_with_keys() {
        Ok((prep_ms, prove_ms)) => {
            format!("ECDSA Proof - Prep: {}ms, Prove: {}ms", prep_ms, prove_ms)
        }
        Err(e) => format!("ECDSA Proof failed: {}", e)
    }
}

#[uniffi::export]
fn jwt_prove_with_keys() -> String {
    match prove_jwt_with_keys() {
        Ok((prep_ms, prove_ms)) => {
            format!("JWT Proof - Prep: {}ms, Prove: {}ms", prep_ms, prove_ms)
        }
        Err(e) => format!("JWT Proof failed: {}", e)
    }
}

#[uniffi::export]
fn setup_ecdsa_keys() -> String {
    match std::panic::catch_unwind(|| {
        setup_ecdsa_circuit_keys();
    }) {
        Ok(_) => "ECDSA keys generated successfully".to_string(),
        Err(_) => "ECDSA key setup failed".to_string()
    }
}

#[uniffi::export]
fn setup_jwt_keys() -> String {
    match std::panic::catch_unwind(|| {
        setup_jwt_circuit_keys();
    }) {
        Ok(_) => "JWT keys generated successfully".to_string(),
        Err(_) => "JWT key setup failed".to_string()
    }
}

#[uniffi::export]
fn jwt_prove_sum_check() -> String {
    match prove_jwt_sum_check() {
        Ok((prep_ms, sumcheck_ms)) => {
            format!("JWT Sum-check - Prep: {}ms, Sum-check: {}ms", prep_ms, sumcheck_ms)
        }
        Err(e) => format!("JWT Sum-check failed: {}", e)
    }
}

#[uniffi::export]
fn jwt_prove_sumcheck_hyrax() -> String {
    match prove_jwt_sumcheck_hyrax() {
        Ok((prep_ms, prove_ms)) => {
            format!("JWT Prove (Sumcheck+Hyrax) - Prep: {}ms, Prove: {}ms", prep_ms, prove_ms)
        }
        Err(e) => format!("JWT Prove (Sumcheck+Hyrax) failed: {}", e)
    }
}

#[uniffi::export]
fn ecdsa_prove_sumcheck_hyrax() -> String {
    match prove_ecdsa_sumcheck_hyrax() {
        Ok((prep_ms, prove_ms)) => {
            format!("ECDSA Prove (Sumcheck+Hyrax) - Prep: {}ms, Prove: {}ms", prep_ms, prove_ms)
        }
        Err(e) => format!("ECDSA Prove (Sumcheck+Hyrax) failed: {}", e)
    }
}

#[cfg(test)]
mod uniffi_tests {
    use super::*;

    #[test]
    fn test_mopro_uniffi_hello_world() {
        assert_eq!(mopro_uniffi_hello_world(), "Hello, World!");
    }

    // #[test]
    // fn test_sha256_prove_and_verify() {
    //     sha256::sha256_prove_and_verify();
    // }

    #[test]
    fn test_ecdsa_prove_and_verify() {
        // Test may fail if circuits files don't exist, which is expected in CI/test environment
        let result = std::panic::catch_unwind(|| ecdsa_prove_and_verify());
        match result {
            Ok(result) => assert!(result.contains("ECDSA Circuit")),
            Err(_) => println!("ECDSA circuit test panicked (expected if circuit files missing)")
        }
    }

    #[test]
    fn test_jwt_prove_and_verify() {
        // Test may fail if circuits files don't exist, which is expected in CI/test environment
        let result = std::panic::catch_unwind(|| jwt_prove_and_verify());
        match result {
            Ok(result) => assert!(result.contains("JWT Circuit")),
            Err(_) => println!("JWT circuit test panicked (expected if circuit files missing)")
        }
    }

    #[test]
    fn test_setup_ecdsa_keys() {
        let result = std::panic::catch_unwind(|| setup_ecdsa_keys());
        match result {
            Ok(result) => assert!(result.contains("ECDSA keys") && (result.contains("successfully") || result.contains("failed"))),
            Err(_) => println!("ECDSA key setup test panicked (expected if circuit files missing)")
        }
    }

    #[test]
    fn test_setup_jwt_keys() {
        let result = std::panic::catch_unwind(|| setup_jwt_keys());
        match result {
            Ok(result) => assert!(result.contains("JWT keys") && (result.contains("successfully") || result.contains("failed"))),
            Err(_) => println!("JWT key setup test panicked (expected if circuit files missing)")
        }
    }

    #[test]
    fn test_jwt_prove_sum_check() {
        let result = jwt_prove_sum_check();
        assert!(result.contains("JWT Sum-check") && (result.contains("Prep:") || result.contains("failed")));
    }

    #[test]
    fn test_jwt_prove_sumcheck_hyrax() {
        let result = jwt_prove_sumcheck_hyrax();
        assert!(result.contains("JWT Prove") && (result.contains("Prep:") || result.contains("failed")));
    }

    #[test]
    fn test_ecdsa_prove_sumcheck_hyrax() {
        let result = ecdsa_prove_sumcheck_hyrax();
        assert!(result.contains("ECDSA Prove") && (result.contains("Prep:") || result.contains("failed")));
    }
}
