//
//  OAuthConfig.swift
//  OmniChat
//
//  Per-provider OAuth configuration.
//

import Foundation

/// OAuth configuration for a specific provider.
///
/// This struct contains all the information needed to initiate an OAuth 2.0 flow
/// for a given provider. It supports standard OAuth parameters including PKCE
/// (Proof Key for Code Exchange) which is required for public clients (mobile apps).
///
/// ## Example Usage
/// ```swift
/// let config = OAuthConfig(
///     clientID: "your-client-id.apps.googleusercontent.com",
///     authURL: "https://accounts.google.com/o/oauth2/v2/auth",
///     tokenURL: "https://oauth2.googleapis.com/token",
///     scopes: ["openid", "email", "profile"],
///     callbackScheme: "omnichat"
/// )
/// ```
public struct OAuthConfig: Sendable, Codable {
    // MARK: - Required Properties

    /// The OAuth client identifier registered with the provider.
    public let clientID: String

    /// The authorization endpoint URL where the user will be redirected to authenticate.
    public let authURL: String

    /// The token endpoint URL for exchanging authorization codes for tokens.
    public let tokenURL: String

    /// Array of OAuth scopes to request.
    public let scopes: [String]

    /// The callback URL scheme for OAuth redirects.
    /// For OmniChat, use: `omnichat`
    public let callbackScheme: String

    // MARK: - Optional Properties

    /// The redirect URI registered with the OAuth provider.
    /// If nil, defaults to `{callbackScheme}://callback`.
    public let redirectURI: String?

    /// The response type for the authorization request.
    /// Defaults to "code" for authorization code flow.
    public let responseType: String

    /// Whether to use PKCE (Proof Key for Code Exchange).
    /// PKCE is strongly recommended for mobile apps and required for public clients.
    /// Defaults to true.
    public let usePKCE: Bool

    /// Additional query parameters to include in the authorization request.
    public let additionalParameters: [String: String]?

    /// The OAuth client secret (optional, not recommended for mobile apps).
    /// For PKCE flows, this should be nil.
    public let clientSecret: String?

    // MARK: - Computed Properties

    /// The full redirect URI used in OAuth flows.
    public var effectiveRedirectURI: String {
        return redirectURI ?? "\(callbackScheme)://callback"
    }

    /// Space-separated scope string for OAuth requests.
    public var scopeString: String {
        return scopes.joined(separator: " ")
    }

    /// The redirect URI used in OAuth flows (alias for effectiveRedirectURI).
    public var redirectURIValue: String {
        return effectiveRedirectURI
    }

    /// The authorization endpoint URL.
    /// Returns nil if authURL is not a valid URL.
    public var authorizeURLValue: URL {
        return URL(string: authURL)!
    }

    /// The token endpoint URL.
    /// Returns nil if tokenURL is not a valid URL.
    public var tokenURLValue: URL {
        return URL(string: tokenURL)!
    }

    // MARK: - Initialization

    /// Creates a new OAuth configuration.
    ///
    /// - Parameters:
    ///   - clientID: The OAuth client identifier.
    ///   - authURL: The authorization endpoint URL string.
    ///   - tokenURL: The token endpoint URL string.
    ///   - scopes: Array of OAuth scopes to request.
    ///   - callbackScheme: The callback URL scheme (e.g., "omnichat").
    ///   - redirectURI: The redirect URI (optional, defaults to `{callbackScheme}://callback`).
    ///   - responseType: The response type (defaults to "code").
    ///   - usePKCE: Whether to use PKCE (defaults to true).
    ///   - additionalParameters: Additional query parameters (optional).
    ///   - clientSecret: The OAuth client secret (optional).
    public init(
        clientID: String,
        authURL: String,
        tokenURL: String,
        scopes: [String],
        callbackScheme: String,
        redirectURI: String? = nil,
        responseType: String = "code",
        usePKCE: Bool = true,
        additionalParameters: [String: String]? = nil,
        clientSecret: String? = nil
    ) {
        self.clientID = clientID
        self.authURL = authURL
        self.tokenURL = tokenURL
        self.scopes = scopes
        self.callbackScheme = callbackScheme
        self.redirectURI = redirectURI
        self.responseType = responseType
        self.usePKCE = usePKCE
        self.additionalParameters = additionalParameters
        self.clientSecret = clientSecret
    }

    // MARK: - Predefined Configurations

    /// OAuth configuration for Google.
    ///
    /// - Parameters:
    ///   - clientID: Your Google OAuth client ID.
    ///   - callbackScheme: The callback URL scheme (should be `omnichat`).
    ///   - additionalScopes: Additional scopes beyond the default (optional).
    /// - Returns: Configured OAuthConfig for Google.
    public static func google(
        clientID: String,
        callbackScheme: String = "omnichat",
        additionalScopes: [String] = []
    ) -> OAuthConfig {
        let defaultScopes = ["openid", "email", "profile"]
        let allScopes = defaultScopes + additionalScopes

        return OAuthConfig(
            clientID: clientID,
            authURL: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenURL: "https://oauth2.googleapis.com/token",
            scopes: allScopes,
            callbackScheme: callbackScheme,
            additionalParameters: ["access_type": "offline", "prompt": "consent"]
        )
    }

    /// OAuth configuration for GitHub.
    ///
    /// - Parameters:
    ///   - clientID: Your GitHub OAuth App client ID.
    ///   - clientSecret: Your GitHub OAuth App client secret (optional for PKCE).
    ///   - callbackScheme: The callback URL scheme (should be `omnichat`).
    ///   - scopes: OAuth scopes (defaults to repo, user).
    /// - Returns: Configured OAuthConfig for GitHub.
    public static func github(
        clientID: String,
        clientSecret: String? = nil,
        callbackScheme: String = "omnichat",
        scopes: [String] = ["repo", "user"]
    ) -> OAuthConfig {
        return OAuthConfig(
            clientID: clientID,
            authURL: "https://github.com/login/oauth/authorize",
            tokenURL: "https://github.com/login/oauth/access_token",
            scopes: scopes,
            callbackScheme: callbackScheme,
            usePKCE: clientSecret == nil,  // Use PKCE if no client secret
            clientSecret: clientSecret
        )
    }

    /// Generic OAuth configuration for any provider.
    ///
    /// Use this for custom OAuth providers that follow the standard OAuth 2.0 flow.
    ///
    /// - Parameters:
    ///   - clientID: The OAuth client identifier.
    ///   - authURL: The authorization endpoint URL string.
    ///   - tokenURL: The token endpoint URL string.
    ///   - scopes: Array of OAuth scopes to request.
    ///   - callbackScheme: The callback URL scheme (defaults to `omnichat`).
    ///   - redirectURI: The redirect URI (optional).
    ///   - additionalParameters: Additional query parameters (optional).
    ///   - clientSecret: The OAuth client secret (optional).
    /// - Returns: Configured OAuthConfig.
    public static func generic(
        clientID: String,
        authURL: String,
        tokenURL: String,
        scopes: [String],
        callbackScheme: String = "omnichat",
        redirectURI: String? = nil,
        additionalParameters: [String: String]? = nil,
        clientSecret: String? = nil
    ) -> OAuthConfig {
        return OAuthConfig(
            clientID: clientID,
            authURL: authURL,
            tokenURL: tokenURL,
            scopes: scopes,
            callbackScheme: callbackScheme,
            redirectURI: redirectURI,
            additionalParameters: additionalParameters,
            clientSecret: clientSecret
        )
    }
}
