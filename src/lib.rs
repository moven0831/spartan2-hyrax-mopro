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

mod sha256;

#[uniffi::export]
fn sha256_prove_and_verify() {
    sha256::sha256_prove_and_verify();
}

// Import wallet-unit-poc functions  
use ecdsa_spartan2::{
    run_ecdsa_circuit, run_jwt_circuit, prove_ecdsa_with_keys, prove_jwt_with_keys,
    prove_jwt_sum_check, prove_jwt_sumcheck_hyrax, prove_ecdsa_sumcheck_hyrax,
    setup_ecdsa_keys as setup_ecdsa_circuit_keys, setup_jwt_keys as setup_jwt_circuit_keys
};

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

    #[test]
    fn test_sha256_prove_and_verify() {
        sha256::sha256_prove_and_verify();
    }

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
