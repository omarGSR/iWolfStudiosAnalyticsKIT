//
//  AnalyticsAPIClient.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of sending an analytics batch to the backend.
enum AnalyticsAPIResult: Sendable {

    /// The backend successfully processed the request.
    case success(AnalyticsAPIResponse)

    /// The backend returned a non-2xx HTTP response.
    case httpError(
        statusCode: Int,
        errorCode: String?,
        message: String?,
        retryAfter: String?
    )
}

/// Sends analytics batches to the backend.
struct AnalyticsAPIClient: Sendable {

    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Sends a batch of analytics events.
    func send(
        _ batch: AnalyticsBatch
    ) async throws -> AnalyticsAPIResult {

        let url = AnalyticsEndpoint.eventsBatch.url(
            baseURL: baseURL
        )

        var request = URLRequest(url: url)

        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Accept"
        )

        request.httpBody = try AnalyticsJSONEncoder.encode(batch)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if (200...299).contains(httpResponse.statusCode) {

            let decodedResponse = try JSONDecoder().decode(
                AnalyticsAPIResponse.self,
                from: data
            )

            return .success(decodedResponse)
        }

        let errorResponse = try? JSONDecoder().decode(
            AnalyticsAPIErrorResponse.self,
            from: data
        )

        return .httpError(
            statusCode: httpResponse.statusCode,
            errorCode: errorResponse?.error.code,
            message: errorResponse?.error.message,
            retryAfter: httpResponse.value(
                forHTTPHeaderField: "Retry-After"
            )
        )
    }
}
