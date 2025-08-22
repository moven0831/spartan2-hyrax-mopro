//
//  ContentView.swift
//  MoproApp
//
import SwiftUI

struct ContentView: View {
    @State private var textViewText = ""
    @State private var isProveButtonEnabled = true
    @State private var mobileEnvironmentInitialized = false
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Spartan2-Hyrax Mopro")
                .font(.title)
            
            Button("Initialize Mobile Environment", action: setupMobileEnvironment)
                .disabled(mobileEnvironmentInitialized)
                .accessibilityIdentifier("initializeMobile")
            
            Button("ECDSA Prove & Verify", action: runECDSAProveAndVerify)
                .disabled(!mobileEnvironmentInitialized || !isProveButtonEnabled)
                .accessibilityIdentifier("ecdsaProveVerify")
            
            Button("JWT Prove & Verify", action: runJWTProveAndVerify)
                .disabled(!mobileEnvironmentInitialized || !isProveButtonEnabled)
                .accessibilityIdentifier("jwtProveVerify")
            
            Button("JWT Sum-Check Only", action: runJWTSumCheck)
                .disabled(!mobileEnvironmentInitialized || !isProveButtonEnabled)
                .accessibilityIdentifier("jwtSumCheck")

            ScrollView {
                Text(textViewText)
                    .padding()
                    .accessibilityIdentifier("proof_log")
            }
            .frame(height: 200)
        }
        .padding()
    }
}

extension ContentView {
    
    // Helper function to load bundled resource data
    func loadBundledResourceData(name: String, ext: String) -> Data? {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else {
            textViewText += "Error: Could not find bundled resource \(name).\(ext)\n"
            return nil
        }
        
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch {
            textViewText += "Error loading resource \(name).\(ext): \(error)\n"
            return nil
        }
    }
    
    // Helper function to load bundled resource as string
    func loadBundledResourceString(name: String, ext: String) -> String? {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else {
            textViewText += "Error: Could not find bundled resource \(name).\(ext)\n"
            return nil
        }
        
        do {
            return try String(contentsOfFile: path)
        } catch {
            textViewText += "Error loading resource \(name).\(ext): \(error)\n"
            return nil
        }
    }
    
    // Get documents directory path
    func getDocumentsDirectory() -> String {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].path
    }
    
    // Memory-efficient function to copy bundle resources directly to documents directory
    func copyBundleResourcesDirectly(documentsPath: String) -> Bool {
        let fileManager = FileManager.default
        let docsPath = URL(fileURLWithPath: documentsPath)
        
        // Create necessary directories within the app's sandbox
        let circomDir = docsPath.appendingPathComponent("circom")
        let ecdsaJsDir = circomDir.appendingPathComponent("build/ecdsa/ecdsa_js")
        let jwtJsDir = circomDir.appendingPathComponent("build/jwt/jwt_js")
        let ecdsaInputDir = circomDir.appendingPathComponent("inputs/ecdsa")
        let jwtInputDir = circomDir.appendingPathComponent("inputs/jwt")
        let keysDir = docsPath.appendingPathComponent("wallet-unit-poc/ecdsa-spartan2/keys")
        
        // Create directories
        do {
            try fileManager.createDirectory(at: ecdsaJsDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: jwtJsDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: ecdsaInputDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: jwtInputDir, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: keysDir, withIntermediateDirectories: true)
        } catch {
            DispatchQueue.main.async {
                self.textViewText += "Failed to create directories: \(error)\n"
            }
            return false
        }
        
        // Define files to copy with their sources and destinations
        // Note: WASM files excluded to reduce memory usage and bundle size
        let filesToCopy: [(bundleName: String, bundleExt: String, destination: URL)] = [
            // Circuit files (R1CS and witness only, no WASM)
            ("ecdsa", "r1cs", ecdsaJsDir.appendingPathComponent("ecdsa.r1cs")),
            ("ecdsa", "wtns", ecdsaJsDir.appendingPathComponent("ecdsa.wtns")),
            ("jwt", "r1cs", jwtJsDir.appendingPathComponent("jwt.r1cs")),
            ("jwt", "wtns", jwtJsDir.appendingPathComponent("jwt.wtns")),
            
            // Input files
            ("ecdsa_input", "json", ecdsaInputDir.appendingPathComponent("default.json")),
            ("jwt_input", "json", jwtInputDir.appendingPathComponent("default.json")),
            
            // Key files (these are the large ones)
            ("ecdsa_proving", "key", keysDir.appendingPathComponent("ecdsa_proving.key")),
            ("ecdsa_verifying", "key", keysDir.appendingPathComponent("ecdsa_verifying.key")),
            ("jwt_proving", "key", keysDir.appendingPathComponent("jwt_proving.key")),
            ("jwt_verifying", "key", keysDir.appendingPathComponent("jwt_verifying.key"))
        ]
        
        // Copy each file individually to minimize memory usage
        for (bundleName, bundleExt, destinationURL) in filesToCopy {
            DispatchQueue.main.async {
                self.textViewText += "Copying \(bundleName).\(bundleExt)...\n"
            }
            
            guard let bundleURL = Bundle.main.url(forResource: bundleName, withExtension: bundleExt) else {
                DispatchQueue.main.async {
                    self.textViewText += "Error: Bundle resource \(bundleName).\(bundleExt) not found\n"
                }
                return false
            }
            
            do {
                // Remove existing file if it exists
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                
                // Copy file directly (FileManager handles this efficiently)
                try fileManager.copyItem(at: bundleURL, to: destinationURL)
                
                DispatchQueue.main.async {
                    self.textViewText += "✓ Copied \(bundleName).\(bundleExt)\n"
                }
            } catch {
                DispatchQueue.main.async {
                    self.textViewText += "Failed to copy \(bundleName).\(bundleExt): \(error)\n"
                }
                return false
            }
        }
        
        DispatchQueue.main.async {
            self.textViewText += "All resources copied successfully!\n"
        }
        return true
    }
    
    func setupMobileEnvironment() {
        textViewText += "Initializing mobile environment...\n"
        
        DispatchQueue.global(qos: .userInitiated).async {
            let documentsPath = self.getDocumentsDirectory()
            
            // Copy bundled resources directly to avoid memory issues
            let setupResult = self.copyBundleResourcesDirectly(documentsPath: documentsPath)
            
            if setupResult {
                // Initialize mobile environment
                let initResult = initializeMobileEnvironment(documentsPath: documentsPath)
                
                DispatchQueue.main.async {
                    self.textViewText += "Init result: \(initResult)\n"
                    self.mobileEnvironmentInitialized = true
                    self.textViewText += "Mobile environment ready!\n\n"
                }
            } else {
                DispatchQueue.main.async {
                    self.textViewText += "Failed to copy bundle resources\n"
                }
            }
        }
    }
    
    func runECDSAProveAndVerify() {
        textViewText += "Running ECDSA Prove and Verify...\n"
        isProveButtonEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            let documentsPath = self.getDocumentsDirectory()
            
            let result = mobileEcdsaProveWithKeys(documentsPath: documentsPath)
            
            let end = CFAbsoluteTimeGetCurrent()
            let timeTaken = end - start
            
            DispatchQueue.main.async {
                self.textViewText += "ECDSA Result: \(result)\n"
                self.textViewText += "Time taken: \(String(format: "%.3f", timeTaken))s\n\n"
                self.isProveButtonEnabled = true
            }
        }
    }
    
    func runJWTProveAndVerify() {
        textViewText += "Running JWT Prove and Verify...\n"
        isProveButtonEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            let documentsPath = self.getDocumentsDirectory()
            
            let result = mobileJwtProveWithKeys(documentsPath: documentsPath)
            
            let end = CFAbsoluteTimeGetCurrent()
            let timeTaken = end - start
            
            DispatchQueue.main.async {
                self.textViewText += "JWT Result: \(result)\n"
                self.textViewText += "Time taken: \(String(format: "%.3f", timeTaken))s\n\n"
                self.isProveButtonEnabled = true
            }
        }
    }
    
    func runJWTSumCheck() {
        textViewText += "Running JWT Sumcheck Only...(ideally this should run in background process)\n"
        isProveButtonEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            let documentsPath = self.getDocumentsDirectory()
            
            let result = mobileJwtProveSumCheck(documentsPath: documentsPath)
            
            let end = CFAbsoluteTimeGetCurrent()
            let timeTaken = end - start
            
            DispatchQueue.main.async {
                self.textViewText += "JWT Sum-Check Result: \(result)\n"
                self.textViewText += "Time taken: \(String(format: "%.3f", timeTaken))s\n\n"
                self.isProveButtonEnabled = true
            }
        }
    }
}


