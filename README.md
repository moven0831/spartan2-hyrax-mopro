# zkID Mobile Wallet-Unit-PoC 

Mobile App for [zkID Wallet-Unit-PoC](https://github.com/privacy-ethereum/zkID/tree/main/wallet-unit-poc), support both Android and iOS.

## Getting Started

### 1. Install the Mopro CLI Tool

```sh
cargo install mopro-cli
```

### 2. iOS Projects

### 2(a). Generate iOS Bindings

Build bindings for your project by executing:

```sh
# choose iOS bindings with release mode
mopro build
```

### 2(b). Update Bindings to iOS project

```sh
mopro update
```

### 2(c). Open iOS project

```sh
open ios/MoproApp.xcodeproj
```

## 3. Flutter App

### 3(a). Generate Flutter Bindings

Build bindings for your project by executing:

```sh
# choose Flutter bindings with release mode
mopro build
```

### 3(b). Exclude x86_64 iOS simulator in `mopro_flutter_bindings/ios/mopro_flutter_bindings.podspec`

```podspec
# Flutter.framework does not contain a i386 slice.
# exclude x86_64 since w2c2 is not supported on x86_64-ios simulator build
'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
```

### 3(c). Connect Devices or Run Emulators

```sh
# Check Available Devices
flutter devices

# Start iOS Simulator or Android Emulator
flutter emulator --launch <EMULATOR_TYPE>
```

### 3(d). Run Flutter with Release Mode

```sh
cd flutter
flutter run --release
```
