//
//  AnalyticsJSONEncoder.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Encodes analytics payloads into JSON.
enum AnalyticsJSONEncoder {

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()

        encoder.dateEncodingStrategy = .iso8601

        return try encoder.encode(value)
    }
}
