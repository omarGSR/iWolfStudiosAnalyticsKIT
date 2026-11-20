//
//  AnalyticsAPIClientTests.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 20/11/2026.
//


import Foundation
import Testing
@testable import iWolfAnalyticsKIT

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("Analytics API Client", .serialized)
struct AnalyticsAPIClientTests {

    // MARK: - Mock URLProtocol

    private final class MockURLProtocol: URLProtocol, @unchecked Sendable {

        typealias Handler = @Sendable (URLRequest) throws -> (
            HTTPURLResponse,
            Data
        )

        private static let lock = NSLock()

        nonisolated(unsafe) private static var handlers:
            [String: Handler] = [:]

        static func register(
            host: String,
            handler: @escaping Handler
        ) {
            lock.withLock {
                handlers[host] = handler
            }
        }

        static func unregister(host: String) {
            _ = lock.withLock {
                handlers.removeValue(forKey: host)
            }
        }

        override class func canInit(
            with request: URLRequest
        ) -> Bool {
            true
        }

        override class func canonicalRequest(
            for request: URLRequest
        ) -> URLRequest {
            request
        }

        override func startLoading() {

            do {
                guard let host = request.url?.host else {
                    throw URLError(.badURL)
                }

                let handler = Self.lock.withLock {
                    Self.handlers[host]
                }

                guard let handler else {
                    throw URLError(.badServerResponse)
                }

                let (response, data) = try handler(request)

                client?.urlProtocol(
                    self,
                    didReceive: response,
                    cacheStoragePolicy: .notAllowed
                )

                client?.urlProtocol(
                    self,
                    didLoad: data
                )

                client?.urlProtocolDidFinishLoading(self)

            } catch {
                client?.urlProtocol(
                    self,
                    didFailWithError: error
                )
            }
        }

        override func stopLoading() {}
    }

    // MARK: - Helpers

    private func makeClient(
        host: String
    ) -> AnalyticsAPIClient {

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]

        let session = URLSession(configuration: configuration)

        return AnalyticsAPIClient(
            baseURL: URL(string: "https://\(host)")!,
            session: session
        )
    }

    private func makeBatch() -> AnalyticsBatch {

        AnalyticsBatch(
            appKey: "awakenest",
            installationUUID: UUID(),
            appVersion: "1.0.0",
            osVersion: "macOS 26.0",
            country: "ES",
            events: [
                AnalyticsEvent(eventName: "session_started")
            ]
        )
    }

    private func registerResponse(
        host: String,
        statusCode: Int,
        json: String,
        headers: [String: String] = [:]
    ) {
        MockURLProtocol.register(host: host) { request in

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!

            return (response, Data(json.utf8))
        }
    }

    // MARK: - Tests

    @Test("Send POST request with correct URL and JSON")
    func testRequestStructure() async throws {

        let host = "request-test.example.com"
        let client = makeClient(host: host)
        let batch = makeBatch()

        defer { MockURLProtocol.unregister(host: host) }

        let expectedURL = URL(
            string: "https://\(host)/api/v1/events/batch"
        )!

        MockURLProtocol.register(host: host) { request in

            #expect(request.url == expectedURL)
            #expect(request.httpMethod == "POST")

            #expect(
                request.value(forHTTPHeaderField: "Content-Type")
                == "application/json"
            )

            #expect(
                request.value(forHTTPHeaderField: "Accept")
                == "application/json"
            )

            let body: Data

            if let httpBody = request.httpBody {
                body = httpBody
            } else if let stream = request.httpBodyStream {

                stream.open()
                defer { stream.close() }

                var data = Data()
                let bufferSize = 4096
                let buffer = UnsafeMutablePointer<UInt8>.allocate(
                    capacity: bufferSize
                )

                defer { buffer.deallocate() }

                while stream.hasBytesAvailable {

                    let bytesRead = stream.read(
                        buffer,
                        maxLength: bufferSize
                    )

                    if bytesRead < 0 {
                        throw stream.streamError ?? URLError(.cannotDecodeRawData)
                    }

                    if bytesRead == 0 {
                        break
                    }

                    data.append(buffer, count: bytesRead)
                }

                body = data

            } else {
                Issue.record("Request has no HTTP body")
                return (
                    HTTPURLResponse(
                        url: expectedURL,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"{"data":{"rejected":[]}}"#.utf8)
                )
            }
            let json = try #require(
                JSONSerialization.jsonObject(with: body)
                    as? [String: Any]
            )

            #expect(json["app_key"] as? String == "awakenest")

            #expect(
                json["installation_uuid"] as? String
                == batch.installationUUID.uuidString
            )

            let events = try #require(
                json["events"] as? [[String: Any]]
            )

            #expect(events.count == 1)
            #expect(
                events[0]["event_name"] as? String
                == "session_started"
            )

            let response = HTTPURLResponse(
                url: expectedURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            return (
                response,
                Data(#"{"data":{"rejected":[]}}"#.utf8)
            )
        }

        let result = try await client.send(batch)

        guard case .success(let response) = result else {
            Issue.record("Expected successful response")
            return
        }

        #expect(response.data.rejected.isEmpty)
    }

    @Test("Decode HTTP 200 with rejected events")
    func testPartialSuccess() async throws {

        let host = "partial-test.example.com"
        let client = makeClient(host: host)
        let batch = makeBatch()
        let eventUUID = batch.events[0].id

        defer { MockURLProtocol.unregister(host: host) }

        registerResponse(
            host: host,
            statusCode: 200,
            json: """
            {
                "data": {
                    "rejected": [
                        {
                            "index": 0,
                            "event_uuid": "\(eventUUID.uuidString)",
                            "code": "invalid_session_uuid"
                        }
                    ]
                }
            }
            """
        )

        let result = try await client.send(batch)

        guard case .success(let response) = result else {
            Issue.record("Expected successful response")
            return
        }

        #expect(response.data.rejected.count == 1)
        #expect(response.data.rejected[0].eventUUID == eventUUID)
        #expect(
            response.data.rejected[0].code
            == "invalid_session_uuid"
        )
    }

    @Test("Decode HTTP 400 global error")
    func testGlobalError() async throws {

        let host = "global-error-test.example.com"
        let client = makeClient(host: host)

        defer { MockURLProtocol.unregister(host: host) }

        registerResponse(
            host: host,
            statusCode: 400,
            json: """
            {
                "error": {
                    "code": "invalid_app_key",
                    "message": "Unsupported application."
                }
            }
            """
        )

        let result = try await client.send(makeBatch())

        guard case .httpError(
            let statusCode,
            let errorCode,
            let message,
            _
        ) = result else {
            Issue.record("Expected HTTP error")
            return
        }

        #expect(statusCode == 400)
        #expect(errorCode == "invalid_app_key")
        #expect(message == "Unsupported application.")
    }

    @Test("Preserve Retry-After header for HTTP 429")
    func testRateLimit() async throws {

        let host = "rate-limit-test.example.com"
        let client = makeClient(host: host)

        defer { MockURLProtocol.unregister(host: host) }

        registerResponse(
            host: host,
            statusCode: 429,
            json: """
            {
                "error": {
                    "code": "rate_limit_exceeded",
                    "message": "Too many requests."
                }
            }
            """,
            headers: ["Retry-After": "30"]
        )

        let result = try await client.send(makeBatch())

        guard case .httpError(
            let statusCode,
            let errorCode,
            _,
            let retryAfter
        ) = result else {
            Issue.record("Expected HTTP error")
            return
        }

        #expect(statusCode == 429)
        #expect(errorCode == "rate_limit_exceeded")
        #expect(retryAfter == "30")
    }

    @Test("Preserve HTTP 503 with invalid JSON")
    func testInvalidErrorBody() async throws {

        let host = "invalid-body-test.example.com"
        let client = makeClient(host: host)

        defer { MockURLProtocol.unregister(host: host) }

        registerResponse(
            host: host,
            statusCode: 503,
            json: "<html>Service unavailable</html>"
        )

        let result = try await client.send(makeBatch())

        guard case .httpError(
            let statusCode,
            let errorCode,
            _,
            _
        ) = result else {
            Issue.record("Expected HTTP error")
            return
        }

        #expect(statusCode == 503)
        #expect(errorCode == nil)
    }

    @Test("Throw decoding error for malformed HTTP 200")
    func testMalformedSuccessResponse() async throws {

        let host = "malformed-test.example.com"
        let client = makeClient(host: host)

        defer { MockURLProtocol.unregister(host: host) }

        registerResponse(
            host: host,
            statusCode: 200,
            json: """
            {
                "data": {
                    "unexpected_field": true
                }
            }
            """
        )

        await #expect(throws: DecodingError.self) {
            try await client.send(makeBatch())
        }
    }

    @Test("Propagate network connection failure")
    func testNetworkFailure() async throws {

        let host = "network-test.example.com"
        let client = makeClient(host: host)

        defer { MockURLProtocol.unregister(host: host) }

        MockURLProtocol.register(host: host) { _ in
            throw URLError(.notConnectedToInternet)
        }

        await #expect(throws: URLError.self) {
            try await client.send(makeBatch())
        }
    }
}
