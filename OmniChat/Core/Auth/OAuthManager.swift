//
//  OAuthManager.swift
//  OmniChat
//
//  OAuth authentication using ASWebAuthenticationSession with PKCE and automatic token refresh.
//

import Foundation
import AuthenticationServices
import os

/// Errors that can occur during OAuth authentication flows.
enum OAuthError: Error, Sendable, CustomStringConvertible {
    /// The state parameter in the callback does not match the original request.
    case invalidState
    /// The callback URL is malformed or missing required parameters.
    case invalidCallbackURL
    /// Token refresh failed - the refresh token may have expired.
    case tokenRefreshFailed
    /// The refresh token has expired and re-authentication is required.
    case refreshTokenExpired
    /// A network error occurred during the OAuth flow.
    case networkError(Error)
    /// The user cancelled the authentication flow.
    case cancelled
    /// No OAuth tokens were found for the provider.
    case noTokensFound
    /// PKCE code challenge generation failed.
    case pkceGenerationFailed
    /// The authorization server returned an error.
    case serverError(String)

    var description: String {
        switch self {
        case .invalidState:
            return "Invalid OAuth state - possible CSRF attack."
        case .invalidCallbackURL:
            return "Invalid OAuth callback URL."
        case .tokenRefreshFailed:
            return "Token refresh failed."
        case .refreshTokenExpired:
            return "Refresh token has expired. Please re-authenticate."
        case .networkError(let error):
            return "Network error during OAuth: \(error.localizedDescription)"
        case .cancelled:
            return "Authentication was cancelled."
        case .noTokensFound:
            return "No OAuth tokens found for this provider."
        case .pkceGenerationFailed:
            return "Failed to generate PKCE parameters."
        case .serverError(let message):
            return "Authorization server error: \(message)"
        }
    }

    static func == (lhs: OAuthError, rhs: OAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidState, .invalidState),
             (.invalidCallbackURL, .invalidCallbackURL),
             (.tokenRefreshFailed, .tokenRefreshFailed),
             (.refreshTokenExpired, .refreshTokenExpired),
             (.cancelled, .cancelled),
             (.noTokensFound, .noTokensFound),
             (.pkceGenerationFailed, .pkceGenerationFailed):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.serverError(let lhsMsg), .serverError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .invalidState:
            hasher.combine("invalidState")
        case .invalidCallbackURL:
            hasher.combine("invalidCallbackURL")
        case .tokenRefreshFailed:
            hasher.combine("tokenRefreshFailed")
        case .refreshTokenExpired:
            hasher.combine("refreshTokenExpired")
        case .networkError(let error):
            hasher.combine("networkError")
            hasher.combine(error.localizedDescription)
        case .cancelled:
            hasher.combine("cancelled")
        case .noTokensFound:
            hasher.combine("noTokensFound")
        case .pkceGenerationFailed:
            hasher.combine("pkceGenerationFailed")
        case .serverError(let message):
            hasher.combine("serverError")
            hasher.combine(message)
        }
    }
}

/// Represents OAuth tokens with their associated metadata.
struct OAuthToken: Sendable, Codable {
    /// The access token used for API authentication.
    let accessToken: String
    /// The refresh token used to obtain new access tokens.
    let refreshToken: String?
    /// The token type (usually "Bearer").
    let tokenType: String
    /// The number of seconds until the access token expires.
    let expiresIn: Int?
    /// The scopes granted to this token.
    let scopes: [String]?
    /// The calculated expiry date.
    let expiresAt: Date?

    /// Creates a new OAuth token.
    /// - Parameters:
    ///   - accessToken: The access token string.
    ///   - refreshToken: Optional refresh token.
    ///   - tokenType: The token type (defaults to "Bearer").
    ///   - expiresIn: Seconds until expiry.
    ///   - scopes: Granted scopes.
    ///   - storedExpiry: A pre-stored expiry date (used when loading from Keychain).
    init(
        accessToken: String,
        refreshToken: String? = nil,
        tokenType: String = "Bearer",
        expiresIn: Int? = nil,
        scopes: [String]? = nil,
        storedExpiry: Date? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scopes = scopes
        // Use stored expiry if available, otherwise calculate from expiresIn
        if let storedExpiry {
            self.expiresAt = storedExpiry
        } else if let expiresIn {
            self.expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        } else {
            self.expiresAt = nil
        }
    }

    /// Checks if the token has expired.
    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }

    /// Checks if the token needs refresh (expired or expiring within 5 minutes).
    var needsRefresh: Bool {
        guard let expiresAt else { return false }
        // Refresh if token expires within 5 minutes
        return Date().addingTimeInterval(5 * 60) >= expiresAt
    }
}

/// Manages OAuth authentication flows for AI providers.
///
/// This manager handles:
/// - Authorization code flow with PKCE
/// - Automatic token refresh before expiry
/// - Thread-safe token storage and retrieval
/// - Integration with KeychainManager for secure storage
///
/// ## Example Usage
/// ```swift
/// let oauthManager = OAuthManager.shared
///
/// // Initiate OAuth flow
/// let token = try await oauthManager.authenticate(
///     providerID: providerID,
///     config: oauthConfig
/// )
///
/// // Get valid token (refreshes if needed)
/// let validToken = try await oauthManager.validToken(for: providerID, config: oauthConfig)
///
/// // Manually refresh token
/// let newToken = try await oauthManager.refreshToken(token, config: oauthConfig)
/// ```
@MainActor
final class OAuthManager: NSObject, Sendable {

    // MARK: - Singleton

    /// Shared singleton instance.
    static let shared = OAuthManager()

    // MARK: - Properties

    /// Logger for OAuth operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "OAuth")

    /// Keychain manager for token storage.
    private let keychain = KeychainManager.shared

    /// Active authentication sessions (providerID -> session).
    private var activeSessions: [UUID: ASWebAuthenticationSession] = [:]

    /// In-flight refresh operations to prevent race conditions.
    private var pendingRefreshes: [UUID: Task<OAuthToken, Error>] = [:]

    /// Callback scheme for OAuth redirects.
    private let callbackScheme = "omnichat://oauth/callback"

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Initiates the OAuth authorization flow for a provider.
    ///
    /// This method opens the system browser for the user to authenticate,
    /// then handles the callback and exchanges the authorization code for tokens.
    ///
    /// - Parameters:
    ///   - providerID: The UUID of the provider.
    ///   - config: OAuth configuration for the provider.
    ///   - windowContext: The window to present the authentication session (macOS).
    /// - Returns: The OAuth tokens obtained from the authorization flow.
    /// - Throws: `OAuthError` for various failure conditions.
    func authenticate(
        providerID: UUID,
        config: OAuthConfig,
        windowContext: Any? = nil
    ) async throws -> OAuthToken {
        Self.logger.info("Starting OAuth flow for provider: \(providerID.uuidString)")

        // Generate PKCE parameters using the PKCE struct from PKCE.swift
        // The PKCE.generate() uses CommonCrypto for SHA256 and always succeeds
        let pkce = PKCE.generate()

        // Generate state for CSRF protection
        let state = UUID().uuidString

        // Build authorization URL using the helper from OAuthConfig extension
        guard let authURL = config.authorizationURL(pkce: pkce, state: state) else {
            Self.logger.error("Failed to construct authorization URL")
            throw OAuthError.invalidCallbackURL
        }

        Self.logger.debug("Authorization URL: \(authURL.absoluteString)")

        // Extract callback scheme from redirectURI
        let callbackSchemeValue: String
        if let redirectURL = URL(string: config.effectiveRedirectURI),
           let scheme = redirectURL.scheme {
            callbackSchemeValue = scheme
        } else {
            // Fallback to the callbackScheme from config
            callbackSchemeValue = config.callbackScheme
        }

        // Perform authentication session
        let callbackURL = try await performAuthenticationSession(
            authURL: authURL,
            callbackScheme: callbackSchemeValue,
            providerID: providerID,
            windowContext: windowContext
        )

        // Parse callback URL
        guard let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = callbackComponents.queryItems else {
            Self.logger.error("Invalid callback URL structure")
            throw OAuthError.invalidCallbackURL
        }

        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })

        // Verify state
        guard let returnedState = queryDict["state"],
              returnedState == state else {
            Self.logger.error("State mismatch in OAuth callback")
            throw OAuthError.invalidState
        }

        // Check for error response
        if let error = queryDict["error"] {
            let errorDescription = queryDict["error_description"] ?? error
            Self.logger.error("OAuth error: \(error, privacy: .public)")
            throw OAuthError.serverError(errorDescription)
        }

        // Extract authorization code
        guard let code = queryDict["code"] else {
            Self.logger.error("No authorization code in callback")
            throw OAuthError.invalidCallbackURL
        }

        // Exchange code for tokens
        let token = try await exchangeCodeForToken(
            code: code,
            codeVerifier: pkce.codeVerifier,
            config: config
        )

        // Store tokens in Keychain
        try storeTokens(token: token, for: providerID)

        Self.logger.info("OAuth flow completed successfully for provider: \(providerID.uuidString)")
        return token
    }

    /// Returns a valid access token for a provider, refreshing if necessary.
    ///
    /// This method checks if the current token is expired or about to expire,
    /// and automatically refreshes it using the refresh token if available.
    ///
    /// - Parameters:
    ///   - providerID: The UUID of the provider.
    ///   - config: OAuth configuration for the provider.
    /// - Returns: A valid access token string.
    /// - Throws: `OAuthError` if no tokens exist or refresh fails.
    func validToken(for providerID: UUID, config: OAuthConfig) async throws -> String {
        Self.logger.debug("Getting valid token for provider: \(providerID.uuidString)")

        // Check if there's already a refresh in progress (race condition prevention)
        if let pendingTask = pendingRefreshes[providerID] {
            Self.logger.debug("Waiting for pending refresh for provider: \(providerID.uuidString)")
            let token = try await pendingTask.value
            return token.accessToken
        }

        // Get current token from Keychain
        guard let token = try loadToken(for: providerID) else {
            Self.logger.error("No OAuth tokens found for provider: \(providerID.uuidString)")
            throw OAuthError.noTokensFound
        }

        // Check if token needs refresh
        guard token.needsRefresh else {
            Self.logger.debug("Token is still valid for provider: \(providerID.uuidString)")
            return token.accessToken
        }

        Self.logger.info("Token needs refresh for provider: \(providerID.uuidString)")

        // Perform refresh
        let newToken = try await refreshToken(token, for: providerID, config: config)
        return newToken.accessToken
    }

    /// Refreshes an expired or expiring token.
    ///
    /// - Parameters:
    ///   - token: The current OAuth token to refresh.
    ///   - providerID: The UUID of the provider.
    ///   - config: OAuth configuration for the provider.
    /// - Returns: A new OAuth token with updated access token.
    /// - Throws: `OAuthError` if refresh fails.
    func refreshToken(_ token: OAuthToken, for providerID: UUID, config: OAuthConfig) async throws -> OAuthToken {
        Self.logger.debug("Refreshing token for provider: \(providerID.uuidString)")

        // Check if refresh is already in progress (on MainActor, so no lock needed)
        if let pendingTask = pendingRefreshes[providerID] {
            Self.logger.debug("Using pending refresh task for provider: \(providerID.uuidString)")
            return try await pendingTask.value
        }

        // Create new refresh task
        let refreshTask = Task<OAuthToken, Error> {
            do {
                let newToken = try await self.performTokenRefresh(token, config: config)
                try self.storeTokens(token: newToken, for: providerID)
                Self.logger.info("Token refreshed successfully for provider: \(providerID.uuidString)")
                return newToken
            } catch {
                Self.logger.error("Token refresh failed for provider: \(providerID.uuidString): \(error)")
                throw error
            }
        }

        pendingRefreshes[providerID] = refreshTask

        do {
            let result = try await refreshTask.value
            pendingRefreshes.removeValue(forKey: providerID)
            return result
        } catch {
            pendingRefreshes.removeValue(forKey: providerID)
            throw error
        }
    }

    /// Checks if OAuth tokens exist for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Returns: True if OAuth tokens exist, false otherwise.
    func hasTokens(for providerID: UUID) -> Bool {
        do {
            return try loadToken(for: providerID) != nil
        } catch {
            return false
        }
    }

    /// Clears all OAuth tokens for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    /// - Throws: `KeychainError` if deletion fails.
    func clearTokens(for providerID: UUID) throws {
        Self.logger.info("Clearing OAuth tokens for provider: \(providerID.uuidString)")
        try keychain.deleteOAuthTokens(providerID: providerID)
        activeSessions.removeValue(forKey: providerID)
        pendingRefreshes.removeValue(forKey: providerID)
    }

    /// Cancels any active authentication session for a provider.
    ///
    /// - Parameter providerID: The UUID of the provider.
    func cancelAuthentication(for providerID: UUID) {
        activeSessions.removeValue(forKey: providerID)
        Self.logger.debug("Cancelled authentication for provider: \(providerID.uuidString)")
    }

    // MARK: - Private Methods

    /// Performs the ASWebAuthenticationSession.
    private func performAuthenticationSession(
        authURL: URL,
        callbackScheme: String,
        providerID: UUID,
        windowContext: Any?
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    switch error.code {
                    case .canceledLogin:
                        continuation.resume(throwing: OAuthError.cancelled)
                    default:
                        continuation.resume(throwing: OAuthError.networkError(error))
                    }
                    return
                }

                if let error = error {
                    continuation.resume(throwing: OAuthError.networkError(error))
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidCallbackURL)
                    return
                }

                continuation.resume(returning: callbackURL)
            }

            // Configure session
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            // Store session reference
            activeSessions[providerID] = session

            // Start session
            #if os(iOS) || os(visionOS)
            session.start()
            #elseif os(macOS)
            if !session.start() {
                continuation.resume(throwing: OAuthError.networkError(NSError(domain: "ASWebAuthenticationSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start authentication session"])))
            }
            #endif
        }
    }

    /// Exchanges authorization code for tokens.
    private func exchangeCodeForToken(
        code: String,
        codeVerifier: String,
        config: OAuthConfig
    ) async throws -> OAuthToken {
        Self.logger.debug("Exchanging authorization code for tokens")

        var request = URLRequest(url: config.tokenURLValue)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents: [String] = [
            "grant_type=authorization_code",
            "client_id=\(config.clientID)",
            "code=\(code)",
            "redirect_uri=\(config.effectiveRedirectURI)"
        ]

        // Add PKCE code verifier if enabled
        if config.usePKCE {
            bodyComponents.append("code_verifier=\(codeVerifier)")
        }

        // Add client secret if provided
        if let clientSecret = config.clientSecret {
            bodyComponents.append("client_secret=\(clientSecret)")
        }

        if !config.scopes.isEmpty {
            bodyComponents.append("scope=\(config.scopeString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? config.scopeString)")
        }

        request.httpBody = bodyComponents.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("Token exchange failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw OAuthError.serverError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return OAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            tokenType: tokenResponse.token_type ?? "Bearer",
            expiresIn: tokenResponse.expires_in,
            scopes: tokenResponse.scope?.components(separatedBy: " ")
        )
    }

    /// Performs the actual token refresh network call.
    private func performTokenRefresh(_ token: OAuthToken, config: OAuthConfig) async throws -> OAuthToken {
        guard let refreshToken = token.refreshToken else {
            Self.logger.error("No refresh token available")
            throw OAuthError.refreshTokenExpired
        }

        Self.logger.debug("Performing token refresh")

        var request = URLRequest(url: config.tokenURLValue)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents: [String] = [
            "grant_type=refresh_token",
            "client_id=\(config.clientID)",
            "refresh_token=\(refreshToken)"
        ]

        // Add client secret if provided
        if let clientSecret = config.clientSecret {
            bodyComponents.append("client_secret=\(clientSecret)")
        }

        request.httpBody = bodyComponents.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.networkError(URLError(.badServerResponse))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            Self.logger.error("Token refresh failed with status \(httpResponse.statusCode): \(errorMessage)")

            if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                throw OAuthError.refreshTokenExpired
            }
            throw OAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return OAuthToken(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token ?? refreshToken, // Keep existing if not returned
            tokenType: tokenResponse.token_type ?? "Bearer",
            expiresIn: tokenResponse.expires_in,
            scopes: tokenResponse.scope?.components(separatedBy: " ")
        )
    }

    /// Stores OAuth tokens in Keychain.
    private func storeTokens(token: OAuthToken, for providerID: UUID) throws {
        // Store access token in standard format
        try keychain.saveOAuthTokens(
            providerID: providerID,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiry: token.expiresAt
        )

        Self.logger.debug("Stored OAuth tokens for provider: \(providerID.uuidString)")
    }

    /// Loads OAuth tokens from Keychain.
    private func loadToken(for providerID: UUID) throws -> OAuthToken? {
        do {
            let (accessToken, refreshToken, expiry) = try keychain.readOAuthTokens(providerID: providerID)

            return OAuthToken(
                accessToken: accessToken,
                refreshToken: refreshToken,
                tokenType: "Bearer",
                expiresIn: nil,
                scopes: nil,
                storedExpiry: expiry
            )
        } catch KeychainError.itemNotFound {
            return nil
        }
    }
}

// MARK: - Token Response

/// Response from token endpoint.
private struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let token_type: String?
    let expires_in: Int?
    let scope: String?
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS) || os(visionOS)
        return UIWindow()
        #elseif os(macOS)
        return NSWindow()
        #endif
    }
}
