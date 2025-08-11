//
//  ContentView.swift
//  MoproApp
//
import SwiftUI

struct ContentView: View {
    @State private var textViewText = ""
    
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Spartan2-Hyrax Mopro")
                .font(.title)

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


