//
//  NetworkError.swift
//  OmniChat
//
//  Network-specific error types.
//

import Foundation

/// Errors that can occur during network operations.
enum NetworkError: Error, Sendable, Equatable {
    /// The URL is invalid or malformed.
    case invalidURL

    /// The request timed out.
    case timeout

    /// No network connection is available.
    case noConnection

    /// The response was invalid or unexpected.
    case invalidResponse

    /// Failed to decode the response data.
    case decodingFailed

    /// Failed to encode the request data.
    case encodingFailed

    /// The request was cancelled.
    case cancelled

    /// An unknown network error occurred.
    /// - Parameter description: A description of the error.
    case unknown(String)
}

// MARK: - LocalizedError

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL is invalid."
        case .timeout:
            return "The request timed out."
        case .noConnection:
            return "No network connection is available."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .decodingFailed:
            return "Failed to process the response data."
        case .encodingFailed:
            return "Failed to encode the request data."
        case .cancelled:
            return "The request was cancelled."
        case .unknown(let description):
            return "A network error occurred: \(description)"
        }
    }
}
