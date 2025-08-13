//
//  HTTPClient.swift
//  ISign
//
//  Minimal networking client to talk to your hosted backend.
//

import Foundation

struct BackendConfig {
	// Default to your provided Replit domain (HTTPS)
	static var baseURL: URL { URL(string: "https://10574777-ba50-4eeb-be1f-f2faf3bad46d-00-1mwaadfp1wiuy.riker.replit.dev")! }
}

struct SignStatus: Decodable {
	let status: String
	let message: String?
	let itms_url: String?
	let download_url: String?
}

enum UploadResult {
	case json(SignStatus)
	case data(Data)
}

enum HTTPClientError: Error {
    case invalidResponse
    case httpStatus(Int, String)
    case network(URLError)
    case other(String)
}

final class HTTPClient {
    static func uploadCertificates(p12URL: URL, password: String, mobileprovisionURL: URL) async throws -> SignStatus {
		let url = BackendConfig.baseURL.appendingPathComponent("uploadCert")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		let boundary = "Boundary-\(UUID().uuidString)"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		let body = try buildMultipartBody(boundary: boundary) { builder in
			try builder.appendFile(fieldName: "p12", fileURL: p12URL, fileName: p12URL.lastPathComponent, mimeType: "application/x-pkcs12")
			try builder.appendField(name: "password", value: password)
			try builder.appendFile(fieldName: "mobileprovision", fileURL: mobileprovisionURL, fileName: mobileprovisionURL.lastPathComponent, mimeType: "application/octet-stream")
		}

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else { throw HTTPClientError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw HTTPClientError.httpStatus(http.statusCode, bodyText)
            }
            let decoded = try JSONDecoder().decode(SignStatus.self, from: data)
            return decoded
        } catch {
            if let urlErr = error as? URLError { throw HTTPClientError.network(urlErr) }
            throw HTTPClientError.other(error.localizedDescription)
        }
	}

    static func signIPA(ipaURL: URL) async throws -> UploadResult {
		let url = BackendConfig.baseURL.appendingPathComponent("signIPA")
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		let boundary = "Boundary-\(UUID().uuidString)"
		request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

		let body = try buildMultipartBody(boundary: boundary) { builder in
			try builder.appendFile(fieldName: "file", fileURL: ipaURL, fileName: ipaURL.lastPathComponent, mimeType: "application/octet-stream")
		}

        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            guard let http = response as? HTTPURLResponse else { throw HTTPClientError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw HTTPClientError.httpStatus(http.statusCode, bodyText)
            }
            if let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased(), contentType.contains("application/json") {
                let decoded = try JSONDecoder().decode(SignStatus.self, from: data)
                return .json(decoded)
            }
            return .data(data)
        } catch {
            if let urlErr = error as? URLError { throw HTTPClientError.network(urlErr) }
            throw HTTPClientError.other(error.localizedDescription)
        }
	}
}

// MARK: - Multipart Builder

private struct MultipartBuilder {
	let boundary: String
	var data = Data()

	mutating func appendField(name: String, value: String) throws {
		data.append("--\(boundary)\r\n".data(using: .utf8)!)
		data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
		data.append("\(value)\r\n".data(using: .utf8)!)
	}

	mutating func appendFile(fieldName: String, fileURL: URL, fileName: String, mimeType: String) throws {
		data.append("--\(boundary)\r\n".data(using: .utf8)!)
		data.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
		data.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)

		let _ = fileURL.startAccessingSecurityScopedResource()
		defer { fileURL.stopAccessingSecurityScopedResource() }
		let fileData = try Data(contentsOf: fileURL)
		data.append(fileData)
		data.append("\r\n".data(using: .utf8)!)
	}

	mutating func finalize() {
		data.append("--\(boundary)--\r\n".data(using: .utf8)!)
	}
}

private func buildMultipartBody(boundary: String, build: (inout MultipartBuilder) throws -> Void) throws -> Data {
	var builder = MultipartBuilder(boundary: boundary)
	try build(&builder)
	builder.finalize()
	return builder.data
}


