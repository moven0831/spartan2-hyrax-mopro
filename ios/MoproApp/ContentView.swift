//
//  ContentView.swift
//  MoproApp
//
import SwiftUI

struct ContentView: View {
    @State private var textViewText = ""
    @State private var isProveButtonEnabled = true
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Spartan2-Hyrax Mopro")
                .font(.title)
            
            Button("SHA256 Prove & Verify", action: runSha256ProveAndVerify)
                .disabled(!isProveButtonEnabled)
                .accessibilityIdentifier("sha256ProveVerify")

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
    func runSha256ProveAndVerify() {
        textViewText += "Running SHA256 Prove and Verify...\n"
        isProveButtonEnabled = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            
            sha256ProveAndVerify()
            
            let end = CFAbsoluteTimeGetCurrent()
            let timeTaken = end - start
            
            DispatchQueue.main.async {
                self.textViewText += "SHA256 proof generated and verified successfully!\n"
                self.textViewText += "Time taken: \(String(format: "%.3f", timeTaken))s\n\n"
                self.isProveButtonEnabled = true
            }
        }
    }
}


