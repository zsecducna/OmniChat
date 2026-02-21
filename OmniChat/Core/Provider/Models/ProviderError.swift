//
//  ProviderError.swift
//  OmniChat
//
//  Error types for AI provider operations.
//

import Foundation

// MARK: - ProviderError

/// Errors that can occur during AI provider operations.
///
/// This enum covers all failure modes for provider adapters:
/// - Authentication failures
/// - Network issues
/// - Rate limiting
/// - Server errors
/// - Response parsing errors
/// - Cancellation
///
/// ## Security Note
/// Error messages MUST NOT include API keys, tokens, or other secrets.
/// Use generic descriptions that are safe to log and display.
///
/// ## Example Usage
/// ```swift
/// do {
///     let models = try await provider.fetchModels()
/// } catch let error as ProviderError {
///     switch error {
///     case .invalidAPIKey:
///         // Prompt user to re-enter API key
///     case .rateLimited(let retryAfter):
///         // Show rate limit message with retry time
///     default:
///         // Handle other errors
///     }
/// }
/// ```
enum ProviderError: Error, Sendable, CustomStringConvertible {
    /// The API key is missing, empty, or malformed.
    case invalidAPIKey
    /// Authentication failed (401 Unauthorized).
    case unauthorized
    /// The request was rate limited (429 Too Many Requests).
    case rateLimited(retryAfter: TimeInterval?)
    /// A network error occurred during the request.
    case networkError(underlying: Error?)
    /// The request timed out.
    case timeout
    /// The requested model is not available.
    case modelNotFound(String)
    /// The response could not be parsed.
    case invalidResponse(String?)
    /// The provider returned an error message.
    case providerError(message: String, code: Int?)
    /// Server error (5xx status codes).
    case serverError(statusCode: Int, message: String?)
    /// Request was cancelled by the user.
    case cancelled
    /// OAuth token has expired and refresh failed.
    case tokenExpired
    /// Feature not supported by this provider.
    case notSupported(String)

    var description: String {
        switch self {
        case .invalidAPIKey:
            return "The API key is invalid or missing."
        case .unauthorized:
            return "Authentication failed. Please check your credentials."
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Please retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limited. Please wait and try again."
        case .networkError(let underlying):
            if let error = underlying {
                return "Network error: \(error.localizedDescription)"
            }
            return "A network error occurred."
        case .timeout:
            return "The request timed out."
        case .modelNotFound(let model):
            return "Model '\(model)' not found or not available."
        case .invalidResponse(let detail):
            if let detail = detail {
                return "Invalid response from provider: \(detail)"
            }
            return "Invalid response from provider."
        case .providerError(let message, let code):
            if let code = code {
                return "Provider error (\(code)): \(message)"
            }
            return "Provider error: \(message)"
        case .serverError(let statusCode, let message):
            if let message = message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))"
        case .cancelled:
            return "The request was cancelled."
        case .tokenExpired:
            return "OAuth token has expired. Please re-authenticate."
        case .notSupported(let feature):
            return "\(feature) is not supported by this provider."
        }
    }
}

// MARK: - Equatable Conformance

extension ProviderError: Equatable {
    static func == (lhs: ProviderError, rhs: ProviderError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidAPIKey, .invalidAPIKey),
             (.unauthorized, .unauthorized),
             (.timeout, .timeout),
             (.cancelled, .cancelled),
             (.tokenExpired, .tokenExpired):
            return true
        case (.rateLimited(let l), .rateLimited(let r)):
            return l == r
        case (.networkError, .networkError):
            // Can't compare underlying errors meaningfully
            return true
        case (.modelNotFound(let l), .modelNotFound(let r)):
            return l == r
        case (.invalidResponse(let l), .invalidResponse(let r)):
            return l == r
        case (.providerError(let lm, let lc), .providerError(let rm, let rc)):
            return lm == rm && lc == rc
        case (.serverError(let ls, let lm), .serverError(let rs, let rm)):
            return ls == rs && lm == rm
        case (.notSupported(let l), .notSupported(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - Hashable Conformance

extension ProviderError: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .invalidAPIKey:
            hasher.combine("invalidAPIKey")
        case .unauthorized:
            hasher.combine("unauthorized")
        case .rateLimited(let retryAfter):
            hasher.combine("rateLimited")
            hasher.combine(retryAfter)
        case .networkError:
            hasher.combine("networkError")
        case .timeout:
            hasher.combine("timeout")
        case .modelNotFound(let model):
            hasher.combine("modelNotFound")
            hasher.combine(model)
        case .invalidResponse(let detail):
            hasher.combine("invalidResponse")
            hasher.combine(detail)
        case .providerError(let message, let code):
            hasher.combine("providerError")
            hasher.combine(message)
            hasher.combine(code)
        case .serverError(let statusCode, let message):
            hasher.combine("serverError")
            hasher.combine(statusCode)
            hasher.combine(message)
        case .cancelled:
            hasher.combine("cancelled")
        case .tokenExpired:
            hasher.combine("tokenExpired")
        case .notSupported(let feature):
            hasher.combine("notSupported")
            hasher.combine(feature)
        }
    }
}
