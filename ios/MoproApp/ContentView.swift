//
//  ContentView.swift
//  MoproApp
//
import SwiftUI
import Compression

// Circuit types matching the new Rust API
enum CircuitType: String, CaseIterable {
    case prepare = "Prepare Circuit"
    case show = "Show Circuit"
}

// Operation phases for tracking workflow progress
enum OperationPhase: Int, CaseIterable {
    case idle = 0
    case setup = 1
    case proving = 2
    case verifying = 3
    case complete = 4

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .setup: return "Setup"
        case .proving: return "Prove"
        case .verifying: return "Verify"
        case .complete: return "Done"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .setup: return "gearshape"
        case .proving: return "function"
        case .verifying: return "checkmark.shield"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// Timing metrics parsed from Rust API responses
struct CircuitTimings {
    var setup: Int?
    var prep: Int?
    var prove: Int?
    var verify: Int?
    var total: Int?
}

struct ContentView: View {
    @State private var selectedCircuit: CircuitType = .prepare
    @State private var currentPhase: OperationPhase = .idle
    @State private var isOperating = false
    @State private var assetsInitialized = false

    @State private var setupResult: String?
    @State private var proveResult: String?
    @State private var fullWorkflowResult: String?
    @State private var errorMessage: String?

    @State private var setupTime: Int?
    @State private var proveTimings: CircuitTimings?
    @State private var fullWorkflowTimings: CircuitTimings?

    @State private var failedPhase: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .imageScale(.large)
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    Text("Spartan2-Hyrax Circuits")
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.top)

                // Circuit Selector
                circuitSelectorCard

                // Phase Tracker
                if currentPhase != .idle {
                    phaseTrackerCard
                }

                // Progress Indicator
                if isOperating {
                    progressCard
                }

                // Error Display
                if let error = errorMessage {
                    errorCard(message: error, phase: failedPhase)
                }

                // Operation Cards
                operationCard(
                    title: "Generate Keys",
                    description: "Generate proving and verifying keys (one-time setup)",
                    icon: "key.fill",
                    action: runSetup,
                    result: setupResult,
                    time: setupTime
                )

                operationCard(
                    title: "Generate Proof",
                    description: "Generate proof using existing keys",
                    icon: "function",
                    action: runProve,
                    result: proveResult,
                    timings: proveTimings
                )

                operationCard(
                    title: "Run Full Workflow",
                    description: "Execute complete setup + prove + verify pipeline",
                    icon: "play.circle.fill",
                    action: runFullWorkflow,
                    result: fullWorkflowResult,
                    timings: fullWorkflowTimings,
                    isPrimary: true
                )

                // Reset Button
                if currentPhase != .idle && !isOperating {
                    Button(action: reset) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .onAppear {
            if !assetsInitialized {
                initializeAssets()
            }
        }
    }

    // MARK: - UI Components

    private var circuitSelectorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Circuit")
                .font(.headline)

            HStack(spacing: 0) {
                ForEach(CircuitType.allCases, id: \.self) { circuit in
                    Button(action: {
                        if !isOperating {
                            selectedCircuit = circuit
                            reset()
                        }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: circuit == .prepare ? "key.fill" : "eye.fill")
                                .font(.system(size: 20))
                            Text(circuit.rawValue)
                                .font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedCircuit == circuit ? Color.blue : Color.gray.opacity(0.1))
                        .foregroundColor(selectedCircuit == circuit ? .white : .primary)
                    }
                    .disabled(isOperating)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var phaseTrackerCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(Array(OperationPhase.allCases.dropFirst().enumerated()), id: \.element) { index, phase in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    phaseIndicator(phase: phase)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func phaseIndicator(phase: OperationPhase) -> some View {
        let isActive = currentPhase == phase
        let isComplete = currentPhase.rawValue > phase.rawValue && currentPhase != .idle

        let color: Color = isActive ? .blue : (isComplete ? .green : .gray)
        let icon = isComplete ? "checkmark.circle.fill" : phase.icon

        return VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(phase.displayName)
                .font(.caption)
                .foregroundColor(color)
                .fontWeight(isActive ? .bold : .regular)
        }
        .frame(maxWidth: .infinity)
    }

    private var progressCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)
            Text(currentPhaseText)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private func errorCard(message: String, phase: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.headline)
            }

            if let phase = phase {
                Text("Failed during: \(phase)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.red.opacity(0.8))
            }

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)

            HStack {
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                    failedPhase = nil
                }
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private func operationCard(
        title: String,
        description: String,
        icon: String,
        action: @escaping () -> Void,
        result: String? = nil,
        time: Int? = nil,
        timings: CircuitTimings? = nil,
        isPrimary: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(isPrimary ? .blue : .gray)
                    .font(.title2)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isPrimary ? .blue : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Button(action: action) {
                Text(title)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isPrimary ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(isPrimary ? .white : .primary)
                    .cornerRadius(8)
            }
            .disabled(isOperating)

            if let result = result {
                resultView(result: result, time: time, timings: timings)
            }
        }
        .padding()
        .background(isPrimary ? Color.blue.opacity(0.05) : Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: isPrimary ? 4 : 2)
    }

    private func resultView(result: String, time: Int?, timings: CircuitTimings?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(result.components(separatedBy: "|").first?.trimmingCharacters(in: .whitespaces) ?? result)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }

            if let timings = timings {
                Divider()
                Text("Timing Breakdown:")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)

                if let setup = timings.setup {
                    timingRow(label: "Setup", ms: setup)
                }
                if let prep = timings.prep {
                    timingRow(label: "Preparation", ms: prep)
                }
                if let prove = timings.prove {
                    timingRow(label: "Proving", ms: prove)
                }
                if let verify = timings.verify {
                    timingRow(label: "Verification", ms: verify)
                }
                if let total = timings.total {
                    Divider()
                    timingRow(label: "Total", ms: total, bold: true)
                }
            } else if let time = time {
                Text("Execution time: \(time)ms (\(String(format: "%.2f", Double(time) / 1000))s)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func timingRow(label: String, ms: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            Spacer()
            Text("\(ms)ms (\(String(format: "%.2f", Double(ms) / 1000))s)")
                .font(.caption2)
                .fontWeight(bold ? .bold : .semibold)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Helper Functions

    private var currentPhaseText: String {
        switch currentPhase {
        case .setup:
            return "Setting up circuit keys..."
        case .proving:
            return "Generating proof..."
        case .verifying:
            return "Verifying proof..."
        case .complete:
            return "Operation complete"
        default:
            return "Processing..."
        }
    }

    private func getDocumentsDirectory() -> String {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].path
    }

    private func parseTimeFromResult(_ result: String) -> Int? {
        let pattern = "(\\d+)ms"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let range = Range(match.range(at: 1), in: result) {
            return Int(result[range])
        }
        return nil
    }

    private func parseDetailedTimings(_ result: String) -> CircuitTimings? {
        var timings = CircuitTimings()

        let patterns = [
            ("Setup", "Setup: (\\d+)ms"),
            ("Prep", "Prep: (\\d+)ms"),
            ("Prove", "Prove: (\\d+)ms"),
            ("Verify", "Verify: (\\d+)ms"),
            ("Total", "Total: (\\d+)ms")
        ]

        for (key, pattern) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
               let range = Range(match.range(at: 1), in: result),
               let value = Int(result[range]) {
                switch key {
                case "Setup": timings.setup = value
                case "Prep": timings.prep = value
                case "Prove": timings.prove = value
                case "Verify": timings.verify = value
                case "Total": timings.total = value
                default: break
                }
            }
        }

        return timings.setup != nil || timings.prep != nil || timings.prove != nil ? timings : nil
    }

    // MARK: - Asset Management

    private func initializeAssets() {
        let documentsPath = getDocumentsDirectory()
        let circomDir = URL(fileURLWithPath: documentsPath).appendingPathComponent("circom")

        do {
            try FileManager.default.createDirectory(at: circomDir, withIntermediateDirectories: true)
            print("Created circom directory: \(circomDir.path)")

            // Compressed assets (will be decompressed during copy)
            let compressedAssets = [
                "jwt.r1cs.gz": "jwt.r1cs",
                "show.r1cs.gz": "show.r1cs"
            ]

            // Regular assets (copied as-is)
            let regularAssets = ["jwt_input.json", "show_input.json"]

            // Decompress and copy compressed assets
            for (compressedName, decompressedName) in compressedAssets {
                let destURL = circomDir.appendingPathComponent(decompressedName)

                // Check if already decompressed
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let fileSize = (try? Data(contentsOf: destURL))?.count ?? 0
                    let fileMB = Double(fileSize) / 1024 / 1024
                    print("Asset already exists: \(decompressedName) (\(String(format: "%.2f", fileMB))MB)")
                    continue
                }

                // Parse filename for bundle lookup
                let components = compressedName.components(separatedBy: ".")
                guard components.count >= 3 else {
                    print("Invalid filename format: \(compressedName)")
                    continue
                }

                let name = components.dropLast(2).joined(separator: ".")
                let ext = "\(components[components.count - 2]).\(components.last!)"

                guard let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) else {
                    print("Asset not found in bundle: \(name).\(ext)")
                    continue
                }

                print("Decompressing asset: \(compressedName) -> \(destURL.path)")

                do {
                    // Read compressed data
                    let compressedData = try Data(contentsOf: bundleURL)
                    let compressedMB = Double(compressedData.count) / 1024 / 1024
                    print("Read compressed data: \(String(format: "%.2f", compressedMB))MB")

                    // Decompress using Swift's Compression framework
                    let decompressedData = try compressedData.gunzipped()
                    let decompressedMB = Double(decompressedData.count) / 1024 / 1024
                    print("Decompressed data: \(String(format: "%.2f", decompressedMB))MB")

                    // Write to destination
                    try decompressedData.write(to: destURL)
                    print("Successfully decompressed \(decompressedName): \(String(format: "%.2f", compressedMB))MB -> \(String(format: "%.2f", decompressedMB))MB")
                } catch {
                    print("Failed to decompress \(compressedName): \(error)")
                    errorMessage = "Failed to decompress \(compressedName): \(error.localizedDescription)"
                }
            }

            // Copy regular assets (no decompression needed)
            for asset in regularAssets {
                let components = asset.components(separatedBy: ".")
                guard components.count >= 2 else { continue }

                let name = components.dropLast().joined(separator: ".")
                let ext = components.last!

                if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
                    let destURL = circomDir.appendingPathComponent(asset)

                    if !FileManager.default.fileExists(atPath: destURL.path) {
                        print("Copying asset: \(asset) -> \(destURL.path)")
                        try FileManager.default.copyItem(at: bundleURL, to: destURL)
                        let bytes = (try? Data(contentsOf: destURL))?.count ?? 0
                        print("Copied \(asset) (\(bytes) bytes)")
                    } else {
                        print("Asset already exists: \(asset)")
                    }
                }
            }

            assetsInitialized = true
            print("Asset initialization completed")
        } catch {
            print("Failed to initialize assets: \(error)")
            errorMessage = "Failed to initialize assets: \(error.localizedDescription)"
        }
    }


    // MARK: - Operations

    private func runSetup() {
        currentPhase = .setup
        isOperating = true
        errorMessage = nil
        failedPhase = nil
        setupResult = nil
        setupTime = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let documentsPath = getDocumentsDirectory()

            let result: String
            switch selectedCircuit {
            case .prepare:
                result = setupPrepareKeys(documentsPath: documentsPath)
            case .show:
                result = setupShowKeys(documentsPath: documentsPath)
            }

            let isError = result.contains("failed") || result.contains("error") || result.contains("Error")

            DispatchQueue.main.async {
                if isError {
                    failedPhase = "Key Setup"
                    errorMessage = result
                    currentPhase = .idle
                } else {
                    setupResult = result
                    setupTime = parseTimeFromResult(result)
                    currentPhase = .complete
                }
                isOperating = false
            }
        }
    }

    private func runProve() {
        currentPhase = .proving
        isOperating = true
        errorMessage = nil
        failedPhase = nil
        proveResult = nil
        proveTimings = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let documentsPath = getDocumentsDirectory()

            let result: String
            switch selectedCircuit {
            case .prepare:
                result = provePrepareCircuit(documentsPath: documentsPath)
            case .show:
                result = proveShowCircuit(documentsPath: documentsPath)
            }

            let isError = result.contains("failed") || result.contains("error") || result.contains("Error")

            DispatchQueue.main.async {
                if isError {
                    // Parse which phase failed
                    if result.lowercased().contains("prep") {
                        failedPhase = "Preparation Phase"
                    } else if result.lowercased().contains("prov") {
                        failedPhase = "Proving Phase"
                    } else if result.lowercased().contains("verif") {
                        failedPhase = "Verification Phase"
                    } else {
                        failedPhase = "Prove Workflow"
                    }
                    errorMessage = result
                    currentPhase = .idle
                    isOperating = false
                } else {
                    proveResult = result
                    proveTimings = parseDetailedTimings(result)
                    currentPhase = .verifying

                    // Simulate verification phase
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        currentPhase = .complete
                        isOperating = false
                    }
                }
            }
        }
    }

    private func runFullWorkflow() {
        currentPhase = .setup
        isOperating = true
        errorMessage = nil
        failedPhase = nil
        fullWorkflowResult = nil
        fullWorkflowTimings = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let documentsPath = getDocumentsDirectory()

            // Update to proving phase
            DispatchQueue.main.async {
                currentPhase = .proving
            }

            let result: String
            switch selectedCircuit {
            case .prepare:
                result = runPrepareCircuit(documentsPath: documentsPath)
            case .show:
                result = runShowCircuit(documentsPath: documentsPath)
            }

            // Check for errors in result
            let isError = result.contains("failed") || result.contains("error") || result.contains("Error")

            if isError {
                DispatchQueue.main.async {
                    // Parse which phase failed
                    if result.lowercased().contains("setup") {
                        failedPhase = "Setup Phase"
                    } else if result.lowercased().contains("prep") {
                        failedPhase = "Preparation Phase"
                    } else if result.lowercased().contains("prov") {
                        failedPhase = "Proving Phase"
                    } else if result.lowercased().contains("verif") {
                        failedPhase = "Verification Phase"
                    } else {
                        failedPhase = "Unknown Phase"
                    }

                    errorMessage = result
                    currentPhase = .idle
                    isOperating = false
                }
            } else {
                // Update to verifying phase
                DispatchQueue.main.async {
                    currentPhase = .verifying
                }

                // Small delay for UI feedback
                Thread.sleep(forTimeInterval: 0.5)

                DispatchQueue.main.async {
                    fullWorkflowResult = result
                    fullWorkflowTimings = parseDetailedTimings(result)
                    currentPhase = .complete
                    isOperating = false
                }
            }
        }
    }

    private func reset() {
        currentPhase = .idle
        setupResult = nil
        proveResult = nil
        fullWorkflowResult = nil
        errorMessage = nil
        failedPhase = nil
        setupTime = nil
        proveTimings = nil
        fullWorkflowTimings = nil
    }
}

// MARK: - Data Extension for GZIP Decompression

extension Data {
    enum GzipError: Error {
        case decompressionFailed
    }

    func gunzipped() throws -> Data {
        // Check for gzip magic number
        guard self.count >= 18 && self[0] == 0x1f && self[1] == 0x8b else {
            throw GzipError.decompressionFailed
        }

        // Parse gzip header to find where compressed data starts
        var headerOffset = 10 // Basic header is 10 bytes

        // Check FLG byte (flags)
        let flg = self[3]

        // FEXTRA: Extra field
        if (flg & 0x04) != 0 {
            guard self.count >= headerOffset + 2 else {
                throw GzipError.decompressionFailed
            }
            let xlen = Int(self[headerOffset]) | (Int(self[headerOffset + 1]) << 8)
            headerOffset += 2 + xlen
        }

        // FNAME: Original file name (null-terminated)
        if (flg & 0x08) != 0 {
            while headerOffset < self.count && self[headerOffset] != 0 {
                headerOffset += 1
            }
            headerOffset += 1 // Skip null terminator
        }

        // FCOMMENT: File comment (null-terminated)
        if (flg & 0x10) != 0 {
            while headerOffset < self.count && self[headerOffset] != 0 {
                headerOffset += 1
            }
            headerOffset += 1 // Skip null terminator
        }

        // FHCRC: Header CRC
        if (flg & 0x02) != 0 {
            headerOffset += 2
        }

        // Footer is last 8 bytes (CRC32 + original size)
        guard self.count > headerOffset + 8 else {
            throw GzipError.decompressionFailed
        }

        let footerOffset = self.count - 8
        let compressedData = self[headerOffset..<footerOffset]

        var decompressed = Data()
        let bufferSize = 128 * 1024 // 128KB buffer

        try compressedData.withUnsafeBytes { (sourcePtr: UnsafeRawBufferPointer) -> Void in
            guard let baseAddress = sourcePtr.baseAddress else {
                throw GzipError.decompressionFailed
            }

            let filter = try OutputFilter(.decompress, using: .zlib, writingTo: { (data: Data?) -> Void in
                if let data = data {
                    decompressed.append(data)
                }
            })

            var sourceIndex = 0
            while sourceIndex < compressedData.count {
                let remainingBytes = compressedData.count - sourceIndex
                let chunkSize = remainingBytes < bufferSize ? remainingBytes : bufferSize
                let chunk = Data(bytes: baseAddress.advanced(by: sourceIndex), count: chunkSize)

                try filter.write(chunk)
                sourceIndex += chunkSize
            }

            try filter.finalize()
        }

        guard !decompressed.isEmpty else {
            throw GzipError.decompressionFailed
        }

        return decompressed
    }
}
