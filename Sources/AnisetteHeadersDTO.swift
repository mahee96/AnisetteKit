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

    public init(dictionary: [String: String] = [:]) {
        self.dictionary = dictionary
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
    }

    public var headers: AnisetteHeaders {
        var h = AnisetteHeaders()
        h.machineID       = dictionary[AnisetteConstants.Headers.machineID]
        h.oneTimePassword = dictionary[AnisetteConstants.Headers.oneTimePassword]
        h.localUserID     = dictionary[AnisetteConstants.Headers.localUserID]
        h.routingInfo     = dictionary[AnisetteConstants.Headers.routingInfo]
        h.deviceID        = dictionary[AnisetteConstants.Headers.deviceID]
        h.serialNumber    = dictionary[AnisetteConstants.Headers.serialNumber]
        h.clientInfo      = dictionary[AnisetteConstants.Headers.clientInfo]
        h.userAgent       = dictionary[AnisetteConstants.Headers.userAgent]
        h.date            = dictionary[AnisetteConstants.Headers.clientTime].flatMap(AnisetteClient.parseISO8601Date)
        h.clientTime      = dictionary[AnisetteConstants.Headers.clientTime]
        h.locale          = dictionary[AnisetteConstants.Headers.locale]
        h.timeZone        = dictionary[AnisetteConstants.Headers.timeZone]
        h.contentType     = dictionary[AnisetteConstants.Headers.contentType]
        h.accept          = dictionary[AnisetteConstants.Headers.accept]
        h.rawHeaders      = dictionary
        return h
    }

    public static func toDictionary(from headers: AnisetteHeaders) -> [String: String] {
        AnisetteHeadersDTO(headers: headers).dictionary
    }

    public static func toHeaders(from dictionary: [String: String]) -> AnisetteHeaders {
        AnisetteHeadersDTO(dictionary: dictionary).headers
    }
}
