//
//  AnisetteHeadersDTO.swift
//  AnisetteKit
//
//  Created by Magesh K on 07/09/26.
//  Copyright © 2026 Magesh K. All rights reserved.
//

import Foundation

public struct AnisetteHeadersDTO: Sendable, Equatable {
    public var dictionary: [String: String]
    public var isCaseSensitive: Bool

    public init(dictionary: [String: String] = [:], isCaseSensitive: Bool = false) {
        self.dictionary = dictionary
        self.isCaseSensitive = isCaseSensitive
    }

    public init(headers: AnisetteHeaders) {
        var dict = [String: String]()
        if let v = headers.machineID       { dict[AnisetteConstants.Headers.machineID]       = v }
        if let v = headers.oneTimePassword { dict[AnisetteConstants.Headers.oneTimePassword] = v }
        if let v = headers.localUserID     { dict[AnisetteConstants.Headers.localUserID]     = v }
        if let v = headers.routingInfo     { dict[AnisetteConstants.Headers.routingInfo]     = v }
        if let v = headers.deviceID        { dict[AnisetteConstants.Headers.deviceID]        = v }
        if let v = headers.serialNumber    { dict[AnisetteConstants.Headers.serialNumber]    = v }
        if let v = headers.clientInfo      { dict[AnisetteConstants.Headers.clientInfo]      = v }
        if let v = headers.userAgent       { dict[AnisetteConstants.Headers.userAgent]       = v }
        if let v = headers.clientTime {
            dict[AnisetteConstants.Headers.clientTime] = v
        } else if let d = headers.date {
            dict[AnisetteConstants.Headers.clientTime] = AnisetteClient.formatISO8601Date(d)
        }
        if let v = headers.locale          { dict[AnisetteConstants.Headers.locale]          = v }
        if let v = headers.timeZone        { dict[AnisetteConstants.Headers.timeZone]        = v }
        if let v = headers.contentType     { dict[AnisetteConstants.Headers.contentType]     = v }
        if let v = headers.accept          { dict[AnisetteConstants.Headers.accept]          = v }
        for (k, v) in headers.additionalHeaders {
            dict[k] = v
        }
        self.dictionary = dict
        self.isCaseSensitive = false
    }

    public var headers: AnisetteHeaders {
        var h = AnisetteHeaders()
        h.machineID       = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.machineID]
        h.oneTimePassword = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.oneTimePassword]
        h.localUserID     = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.localUserID]
        h.routingInfo     = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.routingInfo]
        h.deviceID        = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.deviceID]
        h.serialNumber    = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.serialNumber]
        h.clientInfo      = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.clientInfo]
        h.userAgent       = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.userAgent]
        let timeStr       = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.clientTime]
        h.date            = timeStr.flatMap(AnisetteClient.parseISO8601Date)
        h.clientTime      = timeStr
        h.locale          = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.locale]
        h.timeZone        = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.timeZone]
        h.contentType     = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.contentType]
        h.accept          = dictionary[caseSensitive: isCaseSensitive, AnisetteConstants.Headers.accept]
        h.rawHeaders      = dictionary
        return h
    }

    public static func toDictionary(from headers: AnisetteHeaders) -> [String: String] {
        AnisetteHeadersDTO(headers: headers).dictionary
    }

    public static func toHeaders(isCaseSensitive: Bool = false, from dictionary: [String: String]) -> AnisetteHeaders {
        AnisetteHeadersDTO(isCaseSensitive: isCaseSensitive, dictionary: dictionary).headers
    }
}

private extension Dictionary where Key == String, Value == String {
    subscript(caseSensitive caseSensitive: Bool = false, _ key: String) -> String? {
        if caseSensitive {
            return self[key]
        }
        if let exact = self[key] {
            return exact
        }
        return first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }
}