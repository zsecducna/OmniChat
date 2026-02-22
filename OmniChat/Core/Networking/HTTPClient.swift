//
//  HTTPClient.swift
//  OmniChat
//
//  Base URLSession wrapper with streaming support.
//

import Foundation
import os

/// HTTP client for making API requests with streaming support.
///
/// This client wraps `URLSession` and provides:
/// - Streaming support via `bytes(for:)` for Server-Sent Events (SSE)
/// - Configurable headers and timeouts
/// - Automatic error mapping to `ProviderError` types
/// - Cancellation support via Swift Task cancellation
///
/// ## Usage
///
/// ```swift
/// let client = HTTPClient(timeout: 60)
///
/// // Streaming request
/// let bytes = try await client.stream(
///     url: url,
///     headers: ["Authorization": "Bearer token"],
///     body: requestData
/// )
/// for try await byte in bytes {
///     // Process byte
/// }
///
/// // Non-streaming request
/// let data = try await client.request(
///     url: url,
///     method: "GET",
///     headers: [:]
/// )
/// ```
final class HTTPClient: Sendable {
    /// The underlying URLSession used for network requests.
    let session: URLSession

    /// The timeout interval for requests in seconds.
    let timeout: TimeInterval

    /// Logger for HTTP client operations.
    private static let logger = Logger(subsystem: "com.omnichat.networking", category: "HTTPClient")

    /// Creates a new HTTP client with the specified timeout.
    /// - Parameter timeout: The timeout interval for requests in seconds. Defaults to 60.
    init(timeout: TimeInterval = 60) {
        self.timeout = timeout

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 6

        self.session = URLSession(configuration: configuration)
    }

    /// Creates an HTTP client with a custom URLSession configuration.
    /// - Parameters:
    ///   - configuration: The URLSession configuration to use.
    ///   - timeout: The timeout interval for requests in seconds.
    init(configuration: URLSessionConfiguration, timeout: TimeInterval = 60) {
        self.timeout = timeout
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Streaming Requests

    /// Performs a streaming request and returns the async byte stream.
    ///
    /// Use this method for Server-Sent Events (SSE) or other streaming responses.
    /// The returned `AsyncBytes` can be iterated with `for await` syntax.
    ///
    /// - Parameters:
    ///   - url: The URL to request.
    ///   - method: The HTTP method. Defaults to "POST".
    ///   - headers: HTTP headers to include in the request.
    ///   - body: The request body data. Optional.
    /// - Returns: An async byte stream from the response.
    /// - Throws: `ProviderError` for HTTP errors or network failures.
    func stream(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data?
    ) async throws -> URLSession.AsyncBytes {
        Self.logger.debug("Starting streaming request to: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            try validateResponse(response)
            Self.logger.debug("Streaming connection established")
            return bytes
        } catch let error as ProviderError {
            throw error
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch {
            if Task.isCancelled {
                throw ProviderError.cancelled
            }
            throw ProviderError.networkError(underlying: error)
        }
    }

    // MARK: - Non-Streaming Requests

    /// Performs a non-streaming request and returns the data.
    ///
    /// - Parameters:
    ///   - url: The URL to request.
    ///   - method: The HTTP method. Defaults to "GET".
    ///   - headers: HTTP headers to include in the request.
    ///   - body: The request body data. Optional.
    /// - Returns: The response data.
    /// - Throws: `ProviderError` for HTTP errors or network failures.
    func request(
        url: URL,
        method: String = "GET",
        headers: [String: String],
        body: Data? = nil
    ) async throws -> Data {
        Self.logger.debug("Starting request to: \(url.absoluteString), method: \(method)")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response)
            Self.logger.debug("Request completed successfully, received \(data.count) bytes")
            return data
        } catch let error as ProviderError {
            throw error
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch {
            if Task.isCancelled {
                throw ProviderError.cancelled
            }
            throw ProviderError.networkError(underlying: error)
        }
    }

    // MARK: - Response Validation

    /// Validates an HTTP response and throws appropriate errors.
    /// - Parameter response: The URL response to validate.
    /// - Throws: `ProviderError` for invalid responses or HTTP errors.
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Invalid response: not an HTTP response")
            throw ProviderError.invalidResponse("Not an HTTP response")
        }

        Self.logger.debug("Response status code: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401:
            Self.logger.warning("HTTP 401 Unauthorized: invalid credentials for \(httpResponse.url?.absoluteString ?? "unknown URL")")
            throw ProviderError.unauthorized
        case 403:
            Self.logger.warning("HTTP 403 Forbidden: access denied for \(httpResponse.url?.absoluteString ?? "unknown URL")")
            throw ProviderError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            Self.logger.warning("HTTP 429 Rate limited for \(httpResponse.url?.absoluteString ?? "unknown URL"), retry after: \(retryAfter ?? 0) seconds")
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        case 400...499:
            let message = extractErrorMessage(from: httpResponse)
            Self.logger.error("HTTP \(httpResponse.statusCode) client error for \(httpResponse.url?.absoluteString ?? "unknown URL"): \(message ?? "no message")")
            throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
        case 500...599:
            let message = extractErrorMessage(from: httpResponse)
            Self.logger.error("HTTP \(httpResponse.statusCode) server error for \(httpResponse.url?.absoluteString ?? "unknown URL"): \(message ?? "no message")")
            throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: message)
        default:
            Self.logger.error("HTTP \(httpResponse.statusCode) unexpected status code for \(httpResponse.url?.absoluteString ?? "unknown URL")")
            throw ProviderError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    // MARK: - Error Mapping

    /// Maps a URLError to the appropriate ProviderError.
    /// - Parameter urlError: The URL error to map.
    /// - Returns: The corresponding ProviderError.
    private func mapURLError(_ urlError: URLError) -> ProviderError {
        Self.logger.error("URL error: \(urlError.localizedDescription)")

        switch urlError.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkError(underlying: urlError)
        case .cancelled:
            return .cancelled
        case .badURL:
            return .invalidResponse("Invalid URL")
        case .badServerResponse:
            return .invalidResponse("Bad server response")
        default:
            return .networkError(underlying: urlError)
        }
    }

    /// Extracts an error message from an HTTP response.
    /// - Parameter response: The HTTP response.
    /// - Returns: The error message if available, otherwise nil.
    private func extractErrorMessage(from response: HTTPURLResponse) -> String? {
        // Try to get status message from HTTPURLResponse
        // Note: HTTPURLResponse doesn't have a direct statusMessage property,
        // but we can check common headers
        if let message = response.value(forHTTPHeaderField: "X-Error-Message") {
            return message
        }
        return nil
    }
}
