//
//  HomeView.swift
//  ISign
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct HomeView: View {
    // File selection and status
    @State private var showFileImporter: Bool = false
    @State private var selectedIPAURL: URL?
    @State private var statusMessage: String = ""
    @State private var isSharePresented: Bool = false
    @State private var shareFileURL: URL?
    @State private var remoteURLText: String = ""
    @State private var isSigningBusy: Bool = false

    var body: some View {
        Form {
            Section(header: Text("Fișier IPA")) {
                HStack {
                    Image(systemName: "doc.fill")
                    Text(selectedIPAURL?.lastPathComponent ?? "Niciun fișier selectat")
                    Spacer()
                    Button("Selectează") { showFileImporter = true }
                }
            }

            Section(header: Text("Acțiuni")) {
                Button("Deschide în Share Sheet") { presentShareSheet() }
                    .disabled(selectedIPAURL == nil)
                Button {
                    Task { await signWithHostedBackend() }
                } label: {
                    if isSigningBusy { ProgressView() } else { Text("Sign IPA") }
                }
                .disabled(selectedIPAURL == nil || isSigningBusy)
            }

            Section(header: Text("Instalare din link (IPA/PLIST/ITMS)")) {
                TextField("https://.../(ipa|plist) sau itms-services://...", text: $remoteURLText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Lipește din clipboard") {
                        if let s = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) {
                            remoteURLText = s
                        }
                    }
                    Spacer()
                    Button("Deschide") {
                        let trimmed = remoteURLText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let rawURL = URL(string: trimmed), !trimmed.isEmpty else {
                            statusMessage = "Introduceți un link valid (.ipa/.plist sau itms-services)"
                            return
                        }
                        Task { await openInstallURL(rawURL) }
                    }
                }
            }

            if !statusMessage.isEmpty {
                Section(header: Text("Status")) {
                    Text(statusMessage)
                        .foregroundColor(statusMessage.lowercased().contains("eroare") ? .red : .primary)
                        .font(.callout)
                }
            }
        }
        .navigationTitle("Home")
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls): selectedIPAURL = urls.first
            case .failure(let error): statusMessage = "Eroare selectare fișier: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let shareFileURL { ActivityView(activityItems: [shareFileURL]).ignoresSafeArea() }
        }
    }

    // MARK: - Share
    private func presentShareSheet() {
        guard let sourceURL = selectedIPAURL else { return }
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let destURL = tempDir.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destURL.path) { try FileManager.default.removeItem(at: destURL) }
            let _ = sourceURL.startAccessingSecurityScopedResource()
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            shareFileURL = destURL
            isSharePresented = true
        } catch {
            statusMessage = "Eroare pregătire share: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func signWithHostedBackend() async {
        guard let ipaURL = selectedIPAURL else { return }
        isSigningBusy = true
        statusMessage = "Trimitere către backend..."
        defer { isSigningBusy = false }

        do {
            let result = try await HTTPClient.signIPA(ipaURL: ipaURL)
            switch result {
            case .json(let status):
                statusMessage = readableStatus(prefix: "Semnare: ", status.message ?? status.status)
                if let link = status.itms_url ?? status.download_url, let u = URL(string: link) {
                    await openInstallURL(u)
                }
            case .data(let data):
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("signed-\(ipaURL.lastPathComponent)")
                try data.write(to: tmp, options: .atomic)
                shareFileURL = tmp
                isSharePresented = true
                statusMessage = "Semnare reușită. Fișierul semnat a fost generat."
            }
        } catch let err as HTTPClientError {
            switch err {
            case .invalidResponse:
                statusMessage = "Eroare: răspuns invalid de la server. Verifică domeniul sau încearcă din nou."
            case .httpStatus(let code, let body):
                statusMessage = friendlyHTTPError(code: code, body: body)
            case .network(let urlErr):
                statusMessage = friendlyNetworkError(urlErr)
            case .other(let msg):
                statusMessage = "Eroare neașteptată: \(msg)"
            }
        } catch {
            statusMessage = "Eroare neașteptată: \(error.localizedDescription)"
        }
    }

    private func readableStatus(prefix: String, _ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix + (trimmed.isEmpty ? "OK" : trimmed)
    }

    private func friendlyHTTPError(code: Int, body: String) -> String {
        let hint: String
        switch code {
        case 400: hint = "Cerere invalidă. Verifică dacă ai selectat fișierele corecte."
        case 401: hint = "Neautorizat. Dacă serverul cere cheie API, adaug-o în backend."
        case 403: hint = "Interzis. Accesul la endpoint este restricționat."
        case 404: hint = "Endpoint negăsit pe server. Verifică calea (ex: /uploadCert, /signIPA)."
        case 412: hint = "Precondiții neîndeplinite. Încărcă întâi certificatul și profilul."
        case 413: hint = "Fișier prea mare. Serverul limitează dimensiunea uploadului."
        case 415: hint = "Tip de conținut neacceptat. Trebuie multipart/form-data."
        case 429: hint = "Prea multe cereri. Așteaptă puțin și încearcă din nou."
        case 500: hint = "Eroare internă. Serverul a eșuat în timpul semnării."
        case 503: hint = "Serviciu indisponibil. Serverul este inactiv sau supraîncărcat."
        default:  hint = "Eroare server (\(code))."
        }
        let shortBody = body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)
        return "\(hint) Detalii: \(shortBody)"
    }

    private func friendlyNetworkError(_ e: URLError) -> String {
        switch e.code {
        case .notConnectedToInternet: return "Nu ești conectat la internet."
        case .timedOut: return "Conexiunea a expirat. Încearcă din nou."
        case .cannotFindHost: return "Nu pot găsi domeniul serverului. Verifică adresa."
        case .cannotConnectToHost: return "Nu mă pot conecta la server. Asigură-te că rulează."
        case .appTransportSecurityRequiresSecureConnection: return "Conexiune nesigură blocată de iOS. Folosește HTTPS."
        default: return "Eroare de rețea: \(e.localizedDescription)"
        }
    }

    // MARK: - Install helpers
    @MainActor
    private func openInstallURL(_ url: URL) async {
        let lowerScheme = url.scheme?.lowercased()
        if lowerScheme == "itms-services" { _ = await UIApplication.shared.open(url); return }
        if lowerScheme == "http" || lowerScheme == "https" {
            if url.pathExtension.lowercased() == "plist" {
                var comps = URLComponents(); comps.scheme = "itms-services"; comps.host = ""
                comps.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: url.absoluteString)]
                if let itms = comps.url { _ = await UIApplication.shared.open(itms); return }
            } else if url.pathExtension.lowercased() == "ipa" {
                shareFileURL = url; isSharePresented = true; return
            }
        }
        _ = await UIApplication.shared.open(url)
    }
}


