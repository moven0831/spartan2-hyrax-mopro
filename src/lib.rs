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

use ecdsa_spartan2::{
    run_ecdsa_circuit, run_jwt_circuit, prove_ecdsa_with_keys, prove_jwt_with_keys,
    prove_jwt_sum_check, prove_jwt_sumcheck_hyrax, prove_ecdsa_sumcheck_hyrax,
    setup_ecdsa_keys as setup_ecdsa_circuit_keys, setup_jwt_keys as setup_jwt_circuit_keys,
    mobile_prove_ecdsa_with_keys, mobile_prove_jwt_with_keys, mobile_prove_jwt_sum_check
};

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
}
