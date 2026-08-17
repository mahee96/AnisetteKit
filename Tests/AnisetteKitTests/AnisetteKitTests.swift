//
//  AnisetteKitTests.swift
//  AnisetteKit
//
//  Created by Magesh K on 20/07/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import XCTest
@testable import AnisetteKit

final class AnisetteKitTests: XCTestCase {

    func testUnicornAnisetteProvisioningAndHeaders() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AnisetteKitTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        print("[Test] Initializing LocalAnisetteProvider at fresh temp directory: \(tempDir.path)")
        fflush(stdout)
        let libURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/lib/arm64-v8a")
        let provider = try LocalAnisetteProvider(provisioningDir: tempDir) {
            libURL
        }
        let identifier = UUID()

        print("[Test] 1. Testing UNICORN runProvisioningFlowUC (actual online provisioning flow)...")
        fflush(stdout)
        let adiPbUC = try await provider.runProvisioningFlowUC(identifier: identifier)
        print("[Test] UNICORN PROVISIONING SUCCESS! Generated adi.pb size = \(adiPbUC.count) bytes")
        fflush(stdout)

        XCTAssertGreaterThan(adiPbUC.count, 100, "Generated adi.pb size should be > 100 bytes")

        print("[Test] 2. Testing UNICORN getHeadersUC on freshly provisioned adi.pb...")
        fflush(stdout)
        let headers = try await provider.getHeadersUC(identifier: identifier)
        print("[Test] UNICORN GET HEADERS SUCCESS! Received Headers:")
        for (key, val) in headers {
            print("  \(key): \(val)")
        }
        fflush(stdout)

        XCTAssertFalse(headers["X-Apple-I-MD-M"]?.isEmpty ?? true, "X-Apple-I-MD-M should not be empty")
        XCTAssertFalse(headers["X-Apple-I-MD"]?.isEmpty ?? true, "X-Apple-I-MD should not be empty")
        XCTAssertEqual(headers["X-Apple-I-MD-RINFO"], "17106176", "X-Apple-I-MD-RINFO should match expected 17106176")
    }
}




