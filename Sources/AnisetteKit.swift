//
//  AnisetteKit.swift
//  AnisetteKit
//
//  Created by Magesh K on 20/07/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import Foundation
import CommonCrypto
import anisette_core

public struct LocalAnisetteHeaders {
    public let machineID: String
    public let oneTimePassword: String
    public let routingInfo: String
    public let date: Date
}

public enum LocalAnisetteError: LocalizedError {
    case invalidArgument
    case loaderFailed(reason: String)
    case symbolMissing(name: String)
    case readFailure
    case invalidResponse(reason: String)
    case adiError(code: Int32, description: String)
    case librariesNotFound(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidArgument:
            return "Invalid argument passed to local Anisette provider."
        case .loaderFailed(let reason):
            return "Native loader failure: \(reason)"
        case .symbolMissing(let name):
            return "Required native ADI symbol '\(name)' missing."
        case .readFailure:
            return "Failed to read generated local provisioning data (adi.pb)."
        case .invalidResponse(let reason):
            return "Invalid response from Apple provisioning service: \(reason)"
        case .adiError(let code, let description):
            return "ADI native error (\(code)): \(description)"
        case .librariesNotFound(let reason):
            return "ADI libraries missing: \(reason)"
        }
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}

public enum ProvisioningStorage: Equatable, Sendable {
    case disk
    case memory(existingBlob: Data? = nil)
}

public typealias LibraryDirectoryResolver = () throws -> URL

public class LocalAnisetteProvider {
    public static let defaultClientInfo = "<MacBookPro18,3> <macOS;26.5.2;25F84> <com.apple.AuthKit/1 (com.apple.dt.Xcode/26.0)>"
    public static let defaultRoutingInfo = "17106176"
    public static let defaultLocalUserID = "0000000000000000000000000000000000000000000000000000000000000001"
    public static let adiPbFileName = "adi.pb"
    public static let lookupURLString = "https://gsa.apple.com/grandslam/GsService2/lookup"
    public static let contentTypePlist = "text/x-xml-plist"
    public static let requiredLibraryNames = [
        "libstoreservicescore.so",
        "libCoreADI.so"
    ]

    let libDir: URL

    private let provisioningDir: URL
    public let clientInfo: String

    public init(
        provisioningDir: URL,
        clientInfo: String = LocalAnisetteProvider.defaultClientInfo,
        libraryDirectoryResolver: LibraryDirectoryResolver
    ) throws {
        self.provisioningDir = provisioningDir
        self.clientInfo = clientInfo

        let resolvedDir = try libraryDirectoryResolver()
        guard Self.validateLibrariesExist(at: resolvedDir) else {
            throw LocalAnisetteError.librariesNotFound(
                reason: "Required ADI shared libraries (\(Self.requiredLibraryNames.joined(separator: ", "))) could not be found at: \(resolvedDir.path)"
            )
        }

        self.libDir = resolvedDir
    }

    public static func validateLibrariesExist(at directory: URL) -> Bool {
        guard let isDir = (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir else {
            return false
        }
        let fm = FileManager.default
        return requiredLibraryNames.allSatisfy { libName in
            fm.fileExists(atPath: directory.appendingPathComponent(libName).path)
        }
    }

    public func getHeaders(identifier: UUID) async throws -> [String: String] {
        try await getHeaders(identifier: identifier, storage: .disk).headers
    }

    public func getHeaders(
        identifier: UUID,
        storage: ProvisioningStorage = .disk
    ) async throws -> (headers: [String: String], newBlob: Data?) {
#if !os(macOS)
        return try await getHeadersUC(identifier: identifier, storage: storage)
#else
        let (adiPbData, generatedBlob, cleanup) = try await resolveProvisioningBlob(
            identifier: identifier,
            storage: storage
        ) {
            try await self.runProvisioningFlow(identifier: identifier)
        }
        defer { cleanup() }

        let headers = try callGetAnisetteHeaders(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            adiPb: [UInt8](adiPbData)
        )

        return (formatAnisetteHeaders(rawHeaders: headers, identifier: identifier), generatedBlob)
#endif
    }

    public func getHeadersUC(identifier: UUID) async throws -> [String: String] {
        try await getHeadersUC(identifier: identifier, storage: .disk).headers
    }

    public func getHeadersUC(
        identifier: UUID,
        storage: ProvisioningStorage = .disk
    ) async throws -> (headers: [String: String], newBlob: Data?) {
        let (adiPbData, generatedBlob, cleanup) = try await resolveProvisioningBlob(
            identifier: identifier,
            storage: storage
        ) {
            try await self.runProvisioningFlowUC(identifier: identifier)
        }
        defer { cleanup() }

        let headers = try callGetAnisetteHeadersUC(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            adiPb: [UInt8](adiPbData)
        )

        return (formatAnisetteHeaders(rawHeaders: headers, identifier: identifier), generatedBlob)
    }

    private func resolveProvisioningBlob(
        identifier: UUID,
        storage: ProvisioningStorage,
        provisioner: () async throws -> Data
    ) async throws -> (data: Data, generated: Data?, cleanup: () -> Void) {
        let uuidProvDir = provisioningDir.appendingPathComponent(identifier.uuidString.lowercased())
        let adiPbURL = uuidProvDir.appendingPathComponent(LocalAnisetteProvider.adiPbFileName)

        let cleanup: () -> Void = {
            if case .memory = storage {
                try? FileManager.default.removeItem(at: adiPbURL)
                try? FileManager.default.removeItem(at: uuidProvDir)
            }
        }

        switch storage {
        case .disk:
            if !FileManager.default.fileExists(atPath: adiPbURL.path) {
                verboseLog("[AnisetteKit] Native adi.pb missing. Starting automatic local provisioning...")
                let newBlob = try await provisioner()
                try FileManager.default.createDirectory(at: uuidProvDir, withIntermediateDirectories: true, attributes: nil)
                try newBlob.write(to: adiPbURL)
                verboseLog("[AnisetteKit] Provisioning successful! Saved adi.pb locally.")
                return (newBlob, newBlob, cleanup)
            } else {
                let data = try Data(contentsOf: adiPbURL)
                return (data, nil, cleanup)
            }

        case .memory(let existing):
            if let provided = existing, !provided.isEmpty {
                return (provided, nil, cleanup)
            } else {
                verboseLog("[AnisetteKit] Native adi.pb missing in-memory. Starting automatic local provisioning in-memory...")
                let newBlob = try await provisioner()
                return (newBlob, newBlob, cleanup)
            }
        }
    }

    private func formatAnisetteHeaders(rawHeaders: [String: String], identifier: UUID) -> [String: String] {
        var result = [String: String]()
        result["X-Apple-I-MD"]       = rawHeaders["X-Apple-I-MD"] ?? ""
        result["X-Apple-I-MD-M"]     = rawHeaders["X-Apple-I-MD-M"] ?? ""
        result["X-Apple-I-MD-RINFO"] = rawHeaders["X-Apple-I-MD-RINFO"] ?? LocalAnisetteProvider.defaultRoutingInfo
        result["X-Mme-Device-Id"]    = identifier.uuidString.uppercased()

        let sha256 = CommonSHA256(data: Data(identifier.uuidBytes))
        result["X-Apple-I-MD-LU"] = sha256.map { String(format: "%02hhX", $0) }.joined()
        return result
    }

    func callGetAnisetteHeadersUC(libDir: String, provisioningDir: String, identifier: [UInt8], adiPb: [UInt8]) throws -> [String: String] {

        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = get_anisette_headers_uc(libDir, provisioningDir, identifier, adiPb, UInt32(adiPb.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "Unicorn loader returned nil (code: \(res))"])
        }
        let dict = try parseJSONString(String(cString: ptr))
        if let err = dict["error"] {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return dict
    }

    private func callStartProvisionUC(libDir: String, provisioningDir: String, identifier: [UInt8], spim: [UInt8]) throws -> (cpim: Data, session: UInt32) {
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = start_provision_uc(libDir, provisioningDir, identifier, spim, UInt32(spim.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "Unicorn loader returned nil (code: \(res))"])
        }
        let jsonData = String(cString: ptr).data(using: .utf8)!
        guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "AnisetteKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad JSON from start_provision"])
        }
        if let err = dict["error"] as? String {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let cpimBase64 = dict["cpim_base64"] as? String,
              let session = dict["session"] as? UInt32,
              let cpim = Data(base64Encoded: cpimBase64) else {
            throw NSError(domain: "AnisetteKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing/invalid cpim_base64 or session"])
        }
        return (cpim, session)
    }

    private func callEndProvisionUC(libDir: String, provisioningDir: String, identifier: [UInt8], session: UInt32, ptm: [UInt8], tk: [UInt8]) throws -> Data {
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = end_provision_uc(libDir, provisioningDir, identifier, session, ptm, UInt32(ptm.count), tk, UInt32(tk.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "Unicorn loader returned nil (code: \(res))"])
        }
        let dict = try parseJSONString(String(cString: ptr))
        if let err = dict["error"] {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let adiPbBase64 = dict["adi_pb_base64"], let adiPb = Data(base64Encoded: adiPbBase64) else {
            throw NSError(domain: "AnisetteKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing/invalid adi_pb_base64"])
        }
        return adiPb
    }

    private func parseJSONString(_ s: String) throws -> [String: String] {
        let data = s.data(using: .utf8)!
        return (try JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }

    func runProvisioningFlowUC(identifier: UUID) async throws -> Data {

        verboseLog("[AnisetteKit] Fetching provisioning URLs from Apple lookup...")
        var req = URLRequest(url: URL(string: LocalAnisetteProvider.lookupURLString)!)
        req.httpMethod = "GET"
        req.setValue(LocalAnisetteProvider.contentTypePlist, forHTTPHeaderField: "Content-Type")
        req.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        req.setValue(identifier.uuidString.uppercased(), forHTTPHeaderField: "X-Mme-Device-Id")

        let (lookupData, lookupResp) = try await URLSession.shared.data(for: req)
        verboseLog("[AnisetteKit] Lookup HTTP status: \((lookupResp as? HTTPURLResponse)?.statusCode ?? -1)")

        guard let plist = try PropertyListSerialization.propertyList(from: lookupData, options: [], format: nil) as? [String: Any],
              let urls = plist["urls"] as? [String: String],
              let startURLString = urls["midStartProvisioning"],
              let startURL = URL(string: startURLString),
              let endURLString = urls["midFinishProvisioning"],
              let endURL = URL(string: endURLString) else {
            debugLog("[AnisetteKit] ERROR: Failed to parse provisioning URLs from lookup")
            throw NSError(domain: "AnisetteKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse provisioning URLs from lookup"])
        }
        verboseLog("[AnisetteKit] Got start URL: \(startURLString)")

        verboseLog("[AnisetteKit] Fetching SPIM from Apple...")
        let spim = try await fetchSpim(startURL: startURL, identifier: identifier)
        verboseLog("[AnisetteKit] Got SPIM (\(spim.count) bytes). Running local start_provision via Unicorn loader...")

        let provResult = try callStartProvisionUC(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            spim: [UInt8](spim)
        )
        verboseLog("[AnisetteKit] start_provision OK — session=\(provResult.session), cpim=\(provResult.cpim.count) bytes")

        verboseLog("[AnisetteKit] Sending CPIM to Apple finish provisioning...")
        let (ptm, tk) = try await fetchPtmTk(endURL: endURL, cpim: provResult.cpim, identifier: identifier)
        verboseLog("[AnisetteKit] Got PTM (\(ptm.count) bytes) and TK (\(tk.count) bytes). Running local end_provision...")

        let adiPb = try callEndProvisionUC(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            session: provResult.session,
            ptm: [UInt8](ptm),
            tk: [UInt8](tk)
        )
        verboseLog("[AnisetteKit] end_provision OK — adi.pb size=\(adiPb.count) bytes")
        return adiPb
    }

    private func fetchSpim(startURL: URL, identifier: UUID) async throws -> Data {
        var req = URLRequest(url: startURL)
        req.httpMethod = "POST"
        req.setValue(LocalAnisetteProvider.contentTypePlist, forHTTPHeaderField: "Content-Type")
        req.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        let androidID = identifier.uuidBytes.prefix(8).map { String(format: "%02X", $0) }.joined()
        req.setValue(androidID, forHTTPHeaderField: "X-Mme-Device-Id")

        req.httpBody = try? PropertyListSerialization.data(fromPropertyList: ["Header": [:], "Request": [:]] as [String: Any], format: .xml, options: 0)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        verboseLog("[AnisetteKit] fetchSpim HTTP status: \(statusCode)")
        if statusCode != 200 {
            throw NSError(domain: "AnisetteKit", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Apple SPIM endpoint returned HTTP \(statusCode)"])
        }

        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let response = plist["Response"] as? [String: Any],
              let spimString = response["spim"] as? String,
              let spimData = Data(base64Encoded: spimString) else {
            debugLog("[AnisetteKit] fetchSpim ERROR: plist keys: \((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])?.keys.joined(separator: ", ") ?? "?")")
            throw NSError(domain: "AnisetteKit", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse spim from Apple response"])
        }
        verboseLog("[AnisetteKit] fetchSpim got spim (\(spimData.count) bytes)")
        return spimData
    }

    private func fetchPtmTk(endURL: URL, cpim: Data, identifier: UUID) async throws -> (ptm: Data, tk: Data) {
        var req = URLRequest(url: endURL)
        req.httpMethod = "POST"
        req.setValue(LocalAnisetteProvider.contentTypePlist, forHTTPHeaderField: "Content-Type")
        req.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        let androidID = identifier.uuidBytes.prefix(8).map { String(format: "%02X", $0) }.joined()
        req.setValue(androidID, forHTTPHeaderField: "X-Mme-Device-Id")

        req.httpBody = try? PropertyListSerialization.data(fromPropertyList: ["Header": [:], "Request": ["cpim": cpim.base64EncodedString()]] as [String: Any], format: .xml, options: 0)

        verboseLog("[AnisetteKit] fetchPtmTk posting cpim to Apple...")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
        verboseLog("[AnisetteKit] fetchPtmTk HTTP status: \(statusCode)")
        if statusCode != 200 {
            throw NSError(domain: "AnisetteKit", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Apple PTM/TK endpoint returned HTTP \(statusCode)"])
        }

        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let response = plist["Response"] as? [String: Any],
              let ptmString = response["ptm"] as? String,
              let tkString = response["tk"] as? String,
              let ptm = Data(base64Encoded: ptmString),
              let tk = Data(base64Encoded: tkString) else {
            debugLog("[AnisetteKit] fetchPtmTk ERROR: plist keys: \((try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])?.keys.joined(separator: ", ") ?? "?")")
            throw NSError(domain: "AnisetteKit", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse ptm/tk from Apple response"])
        }
        verboseLog("[AnisetteKit] fetchPtmTk got ptm (\(ptm.count) bytes), tk (\(tk.count) bytes)")
        return (ptm, tk)
    }

    private func CommonSHA256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return Data(hash)
    }
}

#if os(macOS)
private extension LocalAnisetteProvider {

    func callGetAnisetteHeaders(libDir: String, provisioningDir: String, identifier: [UInt8], adiPb: [UInt8]) throws -> [String: String] {
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = get_anisette_headers_c(libDir, provisioningDir, identifier, adiPb, UInt32(adiPb.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "C++ loader returned nil (code: \(res))"])
        }
        let dict = try parseJSONString(String(cString: ptr))
        if let err = dict["error"] {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        return dict
    }

    func callStartProvision(libDir: String, provisioningDir: String, identifier: [UInt8], spim: [UInt8]) throws -> (cpim: Data, session: UInt32) {
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = start_provision_c(libDir, provisioningDir, identifier, spim, UInt32(spim.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "C++ loader returned nil (code: \(res))"])
        }
        let jsonData = String(cString: ptr).data(using: .utf8)!
        guard let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw NSError(domain: "AnisetteKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Bad JSON from start_provision"])
        }
        if let err = dict["error"] as? String {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let cpimBase64 = dict["cpim_base64"] as? String,
              let session = dict["session"] as? UInt32,
              let cpim = Data(base64Encoded: cpimBase64) else {
            throw NSError(domain: "AnisetteKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing/invalid cpim_base64 or session"])
        }
        return (cpim, session)
    }

    func callEndProvision(libDir: String, provisioningDir: String, identifier: [UInt8], session: UInt32, ptm: [UInt8], tk: [UInt8]) throws -> Data {
        var outPtr: UnsafeMutablePointer<CChar>? = nil
        let res = end_provision_c(libDir, provisioningDir, identifier, session, ptm, UInt32(ptm.count), tk, UInt32(tk.count), &outPtr)
        defer { if let p = outPtr { free_c_string(p) } }

        guard let ptr = outPtr else {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: "C++ loader returned nil (code: \(res))"])
        }
        let dict = try parseJSONString(String(cString: ptr))
        if let err = dict["error"] {
            throw NSError(domain: "AnisetteKit", code: Int(res), userInfo: [NSLocalizedDescriptionKey: err])
        }
        guard let adiPbBase64 = dict["adi_pb_base64"], let adiPb = Data(base64Encoded: adiPbBase64) else {
            throw NSError(domain: "AnisetteKit", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing/invalid adi_pb_base64"])
        }
        return adiPb
    }

    func runProvisioningFlow(identifier: UUID) async throws -> Data {

        verboseLog("[AnisetteKit] Fetching provisioning URLs from Apple lookup...")
        var req = URLRequest(url: URL(string: LocalAnisetteProvider.lookupURLString)!)
        req.httpMethod = "GET"
        req.setValue(LocalAnisetteProvider.contentTypePlist, forHTTPHeaderField: "Content-Type")
        req.setValue(clientInfo, forHTTPHeaderField: "X-Mme-Client-Info")
        req.setValue(identifier.uuidString.uppercased(), forHTTPHeaderField: "X-Mme-Device-Id")

        let (lookupData, lookupResp) = try await URLSession.shared.data(for: req)
        verboseLog("[AnisetteKit] Lookup HTTP status: \((lookupResp as? HTTPURLResponse)?.statusCode ?? -1)")

        guard let plist = try PropertyListSerialization.propertyList(from: lookupData, options: [], format: nil) as? [String: Any],
              let urls = plist["urls"] as? [String: String],
              let startURLString = urls["midStartProvisioning"],
              let startURL = URL(string: startURLString),
              let endURLString = urls["midFinishProvisioning"],
              let endURL = URL(string: endURLString) else {
            debugLog("[AnisetteKit] ERROR: Failed to parse provisioning URLs from lookup")
            throw NSError(domain: "AnisetteKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse provisioning URLs from lookup"])
        }
        verboseLog("[AnisetteKit] Got start URL: \(startURLString)")

        verboseLog("[AnisetteKit] Fetching SPIM from Apple...")
        let spim = try await fetchSpim(startURL: startURL, identifier: identifier)
        verboseLog("[AnisetteKit] Got SPIM (\(spim.count) bytes). Running local start_provision via ELF loader...")

        let provResult = try callStartProvision(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            spim: [UInt8](spim)
        )
        verboseLog("[AnisetteKit] start_provision OK — session=\(provResult.session), cpim=\(provResult.cpim.count) bytes")

        verboseLog("[AnisetteKit] Sending CPIM to Apple finish provisioning...")
        let (ptm, tk) = try await fetchPtmTk(endURL: endURL, cpim: provResult.cpim, identifier: identifier)
        verboseLog("[AnisetteKit] Got PTM (\(ptm.count) bytes) and TK (\(tk.count) bytes). Running local end_provision...")

        let adiPb = try callEndProvision(
            libDir: libDir.path,
            provisioningDir: provisioningDir.path,
            identifier: identifier.uuidBytes,
            session: provResult.session,
            ptm: [UInt8](ptm),
            tk: [UInt8](tk)
        )
        verboseLog("[AnisetteKit] end_provision OK — adi.pb size=\(adiPb.count) bytes")
        return adiPb
    }
}
#endif

