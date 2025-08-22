# Spartan2-Hyrax Mopro

PoC for [Spartan2](https://github.com/microsoft/Spartan2) SNARK + Hyrax on iOS App with optimized mobile benchmarking for ECDSA and JWT circuits

## Getting Started

### 1. Install the Mopro CLI Tool

```sh
git clone https://github.com/zkmopro/mopro
cd mopro/cli
cargo install --path .
```

### 2. Generate iOS Bindings

Build bindings for your project by executing:

```sh
# choose iOS bindings with release mode
mopro build
```

### 3. Update Bindings to iOS project

```sh
mopro update
```

### 4. Open iOS project

```sh
open ios/MoproApp.xcodeproj
```

## Mobile Architecture

The project includes a specialized mobile-optimized circuit implementation designed for efficient zero-knowledge proving on iOS devices:

### Unified Mobile Circuit (`wallet-unit-poc/ecdsa-spartan2/src/mobile.rs`)
- **Consolidated Implementation**: Single `MobileCircuit` struct handles both ECDSA and JWT circuits through a `CircuitType` enum
- **Memory-Efficient Witness Loading**: Custom binary witness file parser that directly loads pre-generated `.wtns` files
- **Pre-Generated Resources**: Uses pre-computed R1CS and witness files to avoid memory-intensive circuit compilation on mobile devices

### FFI Integration (`src/lib.rs`)
The following functions are exposed through UniFFI for iOS integration:
- `mobile_ecdsa_prove_with_keys()` - ECDSA proving with prep, prove, and verify timing
- `mobile_jwt_prove_with_keys()` - JWT proving with prep, prove, and verify timing  
- `mobile_jwt_prove_sum_check()` - JWT sum-check proving (faster, proof-of-work style)

### iOS Integration (`ios/MoproApp/ContentView.swift`)
The iOS app provides a complete benchmarking interface with:
- **Resource Management**: Automatic copying of circuit files, witnesses, and cryptographic keys from app bundle to documents directory
- **Background Processing**: All proving operations run on background threads to maintain UI responsiveness
- **Performance Monitoring**: Built-in timing measurement for all proving operations
- **Memory Optimization**: Direct file copying to minimize memory usage during resource setup
