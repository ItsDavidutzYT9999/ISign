//
//  ContentView.swift
//  ISign
//
//  Created by a on 12.08.2025.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationView { HomeView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationView { CertificatesView() }
                .tabItem { Label("Certificates", systemImage: "checkmark.seal") }
        }
    }

}

// UIKit wrapper for UIActivityViewController
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ContentView()
}
