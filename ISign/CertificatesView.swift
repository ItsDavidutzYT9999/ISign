//
//  CertificatesView.swift
//  ISign
//
//  UI to upload p12 + password + mobileprovision to local backend.
//

import SwiftUI
import UniformTypeIdentifiers

struct CertificatesView: View {
    @State private var p12URL: URL?
    @State private var mobileprovisionURL: URL?
    @State private var password: String = ""
    @State private var status: String = ""
    @State private var showP12Picker = false
    @State private var showProvisionPicker = false
    @State private var isBusy = false

    var body: some View {
        Form {
            Section(header: Text("P12 File")) {
                HStack {
                    Image(systemName: "lock.doc")
                    Text(p12URL?.lastPathComponent ?? "No file selected")
                    Spacer()
                    Button("Select File") { showP12Picker = true }
                }
                SecureField("P12 Password", text: $password)
            }

            Section(header: Text("MobileProvision")) {
                HStack {
                    Image(systemName: "doc.text")
                    Text(mobileprovisionURL?.lastPathComponent ?? "No file selected")
                    Spacer()
                    Button("Select File") { showProvisionPicker = true }
                }
            }

            Section {
                Button {
                    Task { await upload() }
                } label: {
                    if isBusy { ProgressView() } else { Text("Încarcă certificatele") }
                }
                .disabled(p12URL == nil || mobileprovisionURL == nil || password.isEmpty || isBusy)
            }

            if !status.isEmpty {
                Section(header: Text("Status")) {
                    Text(status)
                        .foregroundColor(status.lowercased().contains("eroare") ? .red : .primary)
                        .font(.callout)
                }
            }
        }
        .fileImporter(isPresented: $showP12Picker, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): p12URL = urls.first
            case .failure(let error): status = "Eroare selectare p12: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showProvisionPicker, allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): mobileprovisionURL = urls.first
            case .failure(let error): status = "Eroare selectare provisioning: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func upload() async {
        guard let p12URL, let mobileprovisionURL else { return }
        isBusy = true
        status = "Sending to backend..."
        defer { isBusy = false }

        let _ = p12URL.startAccessingSecurityScopedResource()
        let _ = mobileprovisionURL.startAccessingSecurityScopedResource()
        defer {
            p12URL.stopAccessingSecurityScopedResource()
            mobileprovisionURL.stopAccessingSecurityScopedResource()
        }
        do {
            let resp = try await HTTPClient.uploadCertificates(p12URL: p12URL, password: password, mobileprovisionURL: mobileprovisionURL)
            status = resp.message ?? resp.status
        } catch {
            status = "Error at uploading: \(error.localizedDescription)"
        }
    }
}




