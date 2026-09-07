//
//  AnisetteHeaders.swift
//  AnisetteKit
//
//  Created by Magesh K on 07/09/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import Foundation

public struct AnisetteHeaders: Sendable, Equatable {
    public var machineID: String? = nil
    public var oneTimePassword: String? = nil
    public var localUserID: String? = nil
    public var routingInfo: String? = nil
    public var deviceID: String? = nil
    public var serialNumber: String? = nil
    public var clientInfo: String? = nil
    public var userAgent: String? = nil
    public var date: Date? = nil
    public var clientTime: String? = nil
    public var locale: String? = nil
    public var timeZone: String? = nil
    public var contentType: String? = nil
    public var accept: String? = nil
    public var additionalHeaders: [String: String] = [:]
    public var rawHeaders: [String: String] = [:]

    public init() {}

    public init(rawHeaders: [String: String]) {
        self = AnisetteHeadersDTO.toHeaders(from: rawHeaders)
    }

    public static var defaultHeaders: AnisetteHeaders {
        AnisetteHeaders().with {
            $0.localUserID  = AnisetteConstants.defaultLocalUserID
            $0.routingInfo  = AnisetteConstants.defaultRoutingInfo
            $0.serialNumber = AnisetteConstants.defaultSerialNumber
            $0.clientInfo   = AnisetteConstants.defaultClientInfo
            $0.userAgent    = AnisetteConstants.defaultUserAgent
            $0.locale       = AnisetteConstants.defaultLocale
            $0.timeZone     = AnisetteConstants.defaultTimeZone
            $0.contentType  = AnisetteConstants.Headers.contentTypePlist
            $0.accept       = AnisetteConstants.Headers.acceptAll
        }
    }

    public func with(_ modify: (inout AnisetteHeaders) throws -> Void) rethrows -> AnisetteHeaders {
        var copy = self
        try modify(&copy)
        return copy
    }
}
