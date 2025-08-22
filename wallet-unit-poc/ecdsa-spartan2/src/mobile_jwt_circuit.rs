use std::{env::current_dir, fs::File, io::{BufReader, Read}};

use bellpepper_core::{num::AllocatedNum, ConstraintSystem, SynthesisError};
use circom_scotia::{reader::load_r1cs, synthesize};
use spartan2::traits::circuit::SpartanCircuit;
use ff::PrimeField;

use crate::{Scalar, E};

/// Load witness from .wtns file (proper format parsing)
fn load_witness_from_file(filename: impl AsRef<std::path::Path>) -> Vec<Scalar> {
    
    let file = File::open(filename).expect("Failed to open witness file");
    let mut reader = BufReader::new(file);
    
    // Read and verify header "wtns" (4 bytes)
    let mut header = [0u8; 4];
    reader.read_exact(&mut header).expect("Failed to read header");
    if header != [119, 116, 110, 115] { // "wtns" bytes
        panic!("Invalid witness file header");
    }
    
    // Read version (4 bytes)
    let mut version_bytes = [0u8; 4];
    reader.read_exact(&mut version_bytes).expect("Failed to read version");
    let version = u32::from_le_bytes(version_bytes);
    if version > 2 {
        panic!("Unsupported witness file version: {}", version);
    }
    
    // Read number of sections (4 bytes)
    let mut sections_bytes = [0u8; 4];
    reader.read_exact(&mut sections_bytes).expect("Failed to read sections count");
    let num_sections = u32::from_le_bytes(sections_bytes);
    if num_sections != 2 {
        panic!("Invalid number of sections: {}", num_sections);
    }
    
    // Read Section 1 header
    let mut sec_type_bytes = [0u8; 4];
    reader.read_exact(&mut sec_type_bytes).expect("Failed to read section type");
    let sec_type = u32::from_le_bytes(sec_type_bytes);
    if sec_type != 1 {
        panic!("Invalid section type: {}", sec_type);
    }
    
    // Read section size (8 bytes)
    let mut sec_size_bytes = [0u8; 8];
    reader.read_exact(&mut sec_size_bytes).expect("Failed to read section size");
    let sec_size = u64::from_le_bytes(sec_size_bytes);
    if sec_size != 4 + 32 + 4 {
        panic!("Invalid section size: {}", sec_size);
    }
    
    // Read field size (4 bytes)
    let mut field_size_bytes = [0u8; 4];
    reader.read_exact(&mut field_size_bytes).expect("Failed to read field size");
    let field_size = u32::from_le_bytes(field_size_bytes);
    if field_size != 32 {
        panic!("Invalid field size: {}", field_size);
    }
    
    // Skip prime value (32 bytes)
    let mut prime = [0u8; 32];
    reader.read_exact(&mut prime).expect("Failed to read prime");
    
    // Read witness length (4 bytes)
    let mut witness_len_bytes = [0u8; 4];
    reader.read_exact(&mut witness_len_bytes).expect("Failed to read witness length");
    let witness_len = u32::from_le_bytes(witness_len_bytes);
    
    // Read Section 2 header
    let mut sec2_type_bytes = [0u8; 4];
    reader.read_exact(&mut sec2_type_bytes).expect("Failed to read section 2 type");
    let sec2_type = u32::from_le_bytes(sec2_type_bytes);
    if sec2_type != 2 {
        panic!("Invalid section 2 type: {}", sec2_type);
    }
    
    // Read section 2 size (8 bytes)
    let mut sec2_size_bytes = [0u8; 8];
    reader.read_exact(&mut sec2_size_bytes).expect("Failed to read section 2 size");
    let sec2_size = u64::from_le_bytes(sec2_size_bytes);
    if sec2_size != u64::from(witness_len * field_size) {
        panic!("Invalid witness section size: {}", sec2_size);
    }
    
    // Now read the actual witness elements
    let mut witness = Vec::with_capacity(witness_len as usize);
    for _ in 0..witness_len {
        let mut element_bytes = [0u8; 32];
        reader.read_exact(&mut element_bytes).expect("Failed to read witness element");
        
        // Convert bytes to field element
        let scalar = Scalar::from_repr(element_bytes.into())
            .expect("Invalid field element in witness file");
        witness.push(scalar);
    }
    
    witness
}

/// Mobile-compatible JWT circuit that uses pre-generated witnesses
#[derive(Debug, Clone)]
pub struct MobileJWTCircuit;

impl SpartanCircuit<E> for MobileJWTCircuit {
    fn synthesize<CS: ConstraintSystem<Scalar>>(
        &self,
        cs: &mut CS,
        _: &[AllocatedNum<Scalar>],
        _: &[AllocatedNum<Scalar>],
        _: Option<&[Scalar]>,
    ) -> Result<(), SynthesisError> {
        let root = current_dir().unwrap().join("circom");
        let witness_dir = root.join("build/jwt/jwt_js");
        let r1cs_file = witness_dir.join("jwt.r1cs");
        let witness_file = witness_dir.join("jwt.wtns");

        // Load pre-generated witness from file instead of generating it
        let witness = load_witness_from_file(&witness_file);

        // Load R1CS directly without WASM (avoids memory-intensive WitnessCalculator)
        let r1cs = load_r1cs(&r1cs_file);
        synthesize(cs, r1cs, Some(witness))?;
        Ok(())
    }

    fn public_values(&self) -> Result<Vec<Scalar>, SynthesisError> {
        Ok(vec![])
    }
    fn shared<CS: ConstraintSystem<Scalar>>(
        &self,
        _cs: &mut CS,
    ) -> Result<Vec<AllocatedNum<Scalar>>, SynthesisError> {
        Ok(vec![])
    }
    fn precommitted<CS: ConstraintSystem<Scalar>>(
        &self,
        _cs: &mut CS,
        _shared: &[AllocatedNum<Scalar>],
    ) -> Result<Vec<AllocatedNum<Scalar>>, SynthesisError> {
        Ok(vec![])
    }
    fn num_challenges(&self) -> usize {
        0
    }
}