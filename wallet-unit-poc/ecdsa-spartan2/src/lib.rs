//! Library interface for ECDSA and JWT circuit proving using Spartan2

pub use crate::ecdsa_circuit::ECDSACircuit;
pub use crate::jwt_circuit::JWTCircuit;
pub use crate::mobile_ecdsa_circuit::MobileECDSACircuit;
pub use crate::mobile_jwt_circuit::MobileJWTCircuit;
pub use crate::setup::{load_keys, setup_ecdsa_keys, setup_jwt_keys};

use spartan2::{
    provider::T256HyraxEngine,
    spartan::R1CSSNARK,
    traits::{circuit::SpartanCircuit, snark::R1CSSNARKTrait, Engine},
};
use std::time::Instant;
use tracing::info;

pub type E = T256HyraxEngine;
pub type Scalar = <E as Engine>::Scalar;

pub mod ecdsa_circuit;
pub mod jwt_circuit;
pub mod mobile_ecdsa_circuit;
pub mod mobile_jwt_circuit;
pub mod setup;

/// Run a complete circuit benchmark (setup, prep, prove, verify)
pub fn run_circuit<C: SpartanCircuit<E> + Clone + std::fmt::Debug>(circuit: C) -> (u128, u128, u128, u128) {
    // SETUP
    let t0 = Instant::now();
    let (pk, vk) = R1CSSNARK::<E>::setup(circuit.clone()).expect("setup failed");
    let setup_ms = t0.elapsed().as_millis();
    info!(elapsed_ms = setup_ms, "setup");

    // PREPARE
    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!(elapsed_ms = prep_ms, "prep_prove");

    // PROVE
    let t0 = Instant::now();
    let proof =
        R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false).expect("prove failed");
    let prove_ms = t0.elapsed().as_millis();
    info!(elapsed_ms = prove_ms, "prove");

    // VERIFY
    let t0 = Instant::now();
    proof.verify(&vk).expect("verify errored");
    let verify_ms = t0.elapsed().as_millis();
    info!(elapsed_ms = verify_ms, "verify");

    (setup_ms, prep_ms, prove_ms, verify_ms)
}

/// Run ECDSA circuit with complete benchmarking
pub fn run_ecdsa_circuit() -> (u128, u128, u128, u128) {
    info!("Running ECDSA circuit");
    run_circuit(ECDSACircuit)
}

/// Run JWT circuit with complete benchmarking  
pub fn run_jwt_circuit() -> (u128, u128, u128, u128) {
    info!("Running JWT circuit");
    run_circuit(JWTCircuit)
}

/// Prove ECDSA circuit using pre-generated keys
pub fn prove_ecdsa_with_keys() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = ECDSACircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_verifying.key";

    let (pk, vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("ECDSA prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    let proof = R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false)?;
    let prove_ms = t0.elapsed().as_millis();
    info!("ECDSA prove: {} ms", prove_ms);

    // Verify the proof
    proof.verify(&vk)?;
    info!("ECDSA verification successful");

    Ok((prep_ms, prove_ms))
}

/// Prove JWT circuit using pre-generated keys
pub fn prove_jwt_with_keys() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = JWTCircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_verifying.key";

    let (pk, vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("JWT prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    let proof = R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false)?;
    let prove_ms = t0.elapsed().as_millis();
    info!("JWT prove: {} ms", prove_ms);

    // Verify the proof  
    proof.verify(&vk)?;
    info!("JWT verification successful");

    Ok((prep_ms, prove_ms))
}

/// Run only the JWT sum-check portion (no Hyrax PCS)
pub fn prove_jwt_sum_check() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = JWTCircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_verifying.key";

    let (pk, _vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("JWT prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    R1CSSNARK::<E>::prove_sum_check(&pk, circuit.clone(), &mut prep_snark, false)
        .expect("prove_sum_check failed");
    let sumcheck_ms = t0.elapsed().as_millis();
    info!("JWT prove_sum_check: {} ms", sumcheck_ms);

    let total_ms = prep_ms + sumcheck_ms;
    info!(
        "JWT sumcheck TOTAL: {} ms (~{:.1}s)",
        total_ms,
        total_ms as f64 / 1000.0
    );

    Ok((prep_ms, sumcheck_ms))
}

/// Mobile JWT sum-check using pre-generated witnesses (sum-check only, no verification)
pub fn mobile_prove_jwt_sum_check() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = MobileJWTCircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_verifying.key";

    let (pk, _vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("Mobile JWT prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    let _proof = R1CSSNARK::<E>::prove_sum_check(&pk, circuit.clone(), &mut prep_snark, false)
        .expect("prove_sum_check failed");
    let sumcheck_ms = t0.elapsed().as_millis();
    info!("Mobile JWT prove_sum_check: {} ms", sumcheck_ms);

    let total_ms = prep_ms + sumcheck_ms;
    info!(
        "Mobile JWT sumcheck TOTAL: {} ms (~{:.1}s)",
        total_ms,
        total_ms as f64 / 1000.0
    );

    Ok((prep_ms, sumcheck_ms))
}

/// Run JWT proving (sumcheck + Hyrax PCS) without verification
pub fn prove_jwt_sumcheck_hyrax() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = JWTCircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_verifying.key";

    let (pk, _vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("JWT prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false).expect("prove failed");
    let prove_ms = t0.elapsed().as_millis();
    info!("JWT prove: {} ms", prove_ms);

    let total_ms = prep_ms + prove_ms;
    info!(
        "JWT prove sumcheck + Hyrax TOTAL: {} ms (~{:.1}s)",
        total_ms,
        total_ms as f64 / 1000.0
    );

    Ok((prep_ms, prove_ms))
}

/// Run ECDSA proving (sumcheck + Hyrax PCS) without verification
pub fn prove_ecdsa_sumcheck_hyrax() -> Result<(u128, u128), Box<dyn std::error::Error>> {
    let circuit = ECDSACircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_verifying.key";

    let (pk, _vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("ECDSA prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false).expect("prove failed");
    let prove_ms = t0.elapsed().as_millis();
    info!("ECDSA prove: {} ms", prove_ms);

    let total_ms = prep_ms + prove_ms;
    info!(
        "ECDSA prove sumcheck + Hyrax TOTAL: {} ms (~{:.1}s)",
        total_ms,
        total_ms as f64 / 1000.0
    );

    Ok((prep_ms, prove_ms))
}

/// Mobile-compatible ECDSA proving using pre-generated witnesses
pub fn mobile_prove_ecdsa_with_keys() -> Result<(u128, u128, u128), Box<dyn std::error::Error>> {
    let circuit = MobileECDSACircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/ecdsa_verifying.key";

    let (pk, vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("Mobile ECDSA prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    let proof = R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false)?;
    let prove_ms = t0.elapsed().as_millis();
    info!("Mobile ECDSA prove: {} ms", prove_ms);

    // Verify the proof with timing
    let t0 = Instant::now();
    proof.verify(&vk)?;
    let verify_ms = t0.elapsed().as_millis();
    info!("Mobile ECDSA verification: {} ms", verify_ms);

    Ok((prep_ms, prove_ms, verify_ms))
}

/// Mobile-compatible JWT proving using pre-generated witnesses
pub fn mobile_prove_jwt_with_keys() -> Result<(u128, u128, u128), Box<dyn std::error::Error>> {
    let circuit = MobileJWTCircuit;
    let pk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_proving.key";
    let vk_path = "wallet-unit-poc/ecdsa-spartan2/keys/jwt_verifying.key";

    let (pk, vk) = load_keys(pk_path, vk_path)?;

    let t0 = Instant::now();
    let mut prep_snark =
        R1CSSNARK::<E>::prep_prove(&pk, circuit.clone(), false).expect("prep_prove failed");
    let prep_ms = t0.elapsed().as_millis();
    info!("Mobile JWT prep_prove: {} ms", prep_ms);

    let t0 = Instant::now();
    let proof = R1CSSNARK::<E>::prove(&pk, circuit.clone(), &mut prep_snark, false)?;
    let prove_ms = t0.elapsed().as_millis();
    info!("Mobile JWT prove: {} ms", prove_ms);

    // Verify the proof with timing
    let t0 = Instant::now();
    proof.verify(&vk)?;
    let verify_ms = t0.elapsed().as_millis();
    info!("Mobile JWT verification: {} ms", verify_ms);

    Ok((prep_ms, prove_ms, verify_ms))
}