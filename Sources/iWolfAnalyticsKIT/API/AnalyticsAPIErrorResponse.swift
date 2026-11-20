//
//  AnalyticsAPIErrorResponse.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

/// Global error response returned by the Analytics API.
struct AnalyticsAPIErrorResponse: Decodable, Sendable {

    let error: AnalyticsAPIErrorDetail
}

/// Details of a global API error.
struct AnalyticsAPIErrorDetail: Decodable, Sendable {

    /// Backend error code.
    let code: String

    /// Human-readable error description.
    let message: String
}
