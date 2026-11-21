//
//  AnalyticsEndpoint.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//

import Foundation

enum AnalyticsEndpoint: String {
    case eventsBatch = "api/v1/events/batch"
    case remoteConfig = "api/v1/remote"     // not implemented yet in BE

    func url(baseURL: URL) -> URL {
        baseURL.appendingPathComponent(rawValue)
    }
}
