//
//  OAuthConfig.swift
//  OmniChat
//
//  Per-provider OAuth configuration.
//

import Foundation

/// OAuth configuration for a specific provider.
struct OAuthConfig: Codable, Sendable {
    var clientID: String
    var authURL: String
    var tokenURL: String
    var scopes: [String]
    var callbackScheme: String
}
