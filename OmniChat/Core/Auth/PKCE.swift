//
//  PKCE.swift
//  OmniChat
//
//  PKCE (Proof Key for Code Exchange) support for secure OAuth flows.
//  Implements RFC 7636: https://datatracker.ietf.org/doc/html/rfc7636
//

import Foundation
import CommonCrypto
import os

/// PKCE (Proof Key for Code Exchange) parameters for OAuth authorization.
///
/// PKCE provides protection against authorization code interception attacks
/// by requiring the client to prove possession of the code verifier when
/// exchanging the authorization code for tokens.
///
/// ## Example Usage
/// ```swift
/// let pkce = PKCE.generate()
///
/// // Use in authorization URL
/// let authURL = buildAuthURL(
///     codeChallenge: pkce.codeChallenge,
///     codeChallengeMethod: pkce.codeChallengeMethod
/// )
///
/// // Store verifier for later token exchange
/// storeVerifier(pkce.codeVerifier)
///
/// // Use in token exchange after callback
/// let tokens = try await exchangeCode(
///     code: authCode,
///     codeVerifier: pkce.codeVerifier
/// )
/// ```
///
/// ## References
/// - RFC 7636: https://datatracker.ietf.org/doc/html/rfc7636
/// - OAuth 2.0 Security Best Current Practice: https://datatracker.ietf.org/doc/html/draft-ietf-oauth-security-topics
public struct PKCE: Sendable {
    /// The code verifier string (43-128 characters).
    ///
    /// A cryptographically random string that the client creates and uses
    /// to verify the token exchange request. Must be kept secret and not
    /// exposed to the user agent (browser).
    let codeVerifier: String

    /// The code challenge string derived from the verifier.
    ///
    /// For S256 method: SHA256(codeVerifier) encoded as URL-safe base64 without padding.
    /// For plain method: Same as codeVerifier.
    let codeChallenge: String

    /// The challenge method used: "S256" (recommended) or "plain".
    ///
    /// S256 is the recommended method and required by many OAuth providers.
    /// Plain method is only for compatibility with providers that don't support S256.
    let codeChallengeMethod: String

    /// Logger for PKCE operations.
    private static let logger = Logger(subsystem: Constants.BundleID.base, category: "PKCE")

    /// Generates a new PKCE parameter set with S256 challenge method.
    ///
    /// This is the recommended method for PKCE as it provides cryptographic
    /// protection of the verifier during the authorization flow.
    ///
    /// - Returns: A new `PKCE` instance with a random verifier and S256 challenge.
    public static func generate() -> PKCE {
        return generate(method: .s256)
    }

    /// The challenge methods supported by this implementation.
    public enum ChallengeMethod: String, Sendable, Codable, CaseIterable {
        /// SHA256 hash method (recommended, required by most providers).
        case s256 = "S256"
        /// Plain text method (not recommended, for compatibility only).
        case plain = "plain"

        /// Whether this method is recommended for production use.
        public var isRecommended: Bool {
            switch self {
            case .s256: return true
            case .plain: return false
            }
        }
    }

    /// Generates a new PKCE parameter set with the specified challenge method.
    ///
    /// - Parameter method: The challenge method to use (defaults to S256).
    /// - Returns: A new `PKCE` instance with a random verifier and challenge.
    public static func generate(method: ChallengeMethod = .s256) -> PKCE {
        let verifier = generateCodeVerifier()
        let challenge: String
        let methodString: String

        switch method {
        case .s256:
            challenge = generateS256Challenge(from: verifier)
            methodString = method.rawValue
        case .plain:
            challenge = verifier
            methodString = method.rawValue
        }

        Self.logger.debug("Generated PKCE with \(method.rawValue) method, verifier length: \(verifier.count)")

        return PKCE(
            codeVerifier: verifier,
            codeChallenge: challenge,
            codeChallengeMethod: methodString
        )
    }

    /// Creates a PKCE instance from an existing code verifier.
    ///
    /// Use this when you need to reconstruct PKCE parameters from a stored verifier
    /// during token exchange after the authorization callback.
    ///
    /// - Parameters:
    ///   - verifier: The previously generated code verifier.
    ///   - method: The challenge method that was used (defaults to S256).
    /// - Returns: A `PKCE` instance with the computed challenge.
    public static func from(verifier: String, method: ChallengeMethod = .s256) -> PKCE {
        let challenge: String
        switch method {
        case .s256:
            challenge = generateS256Challenge(from: verifier)
        case .plain:
            challenge = verifier
        }

        return PKCE(
            codeVerifier: verifier,
            codeChallenge: challenge,
            codeChallengeMethod: method.rawValue
        )
    }

    /// Validates that a code verifier meets RFC 7636 requirements.
    ///
    /// - Parameter verifier: The verifier string to validate.
    /// - Returns: `true` if the verifier is valid, `false` otherwise.
    public static func isValidVerifier(_ verifier: String) -> Bool {
        // RFC 7636: 43-128 characters, using unreserved characters [A-Z][a-z][0-9]-._~
        let validCharacterSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        guard verifier.count >= 43 && verifier.count <= 128 else {
            return false
        }

        return verifier.unicodeScalars.allSatisfy { validCharacterSet.contains($0) }
    }

    // MARK: - Private Helpers

    /// Generates a cryptographically secure code verifier.
    ///
    /// The verifier is 43-128 characters long using the unreserved character set
    /// [A-Z] / [a-z] / [0-9] / "-" / "." / "_" / "~" as specified in RFC 7636.
    ///
    /// - Returns: A URL-safe base64 encoded random string (64 characters).
    private static func generateCodeVerifier() -> String {
        // Generate 48 random bytes, which encodes to 64 base64 characters
        // This is a good length within the 43-128 character requirement
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

        guard status == errSecSuccess else {
            // Fallback to SystemRandomNumberGenerator if SecRandomCopyBytes fails
            Self.logger.warning("SecRandomCopyBytes failed with status \(status), using fallback")
            return generateCodeVerifierFallback()
        }

        return Data(bytes).urlSafeBase64EncodedString()
    }

    /// Fallback verifier generation using SystemRandomNumberGenerator.
    private static func generateCodeVerifierFallback() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        bytes = (0..<48).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).urlSafeBase64EncodedString()
    }

    /// Generates the S256 code challenge from a verifier.
    ///
    /// The challenge is the SHA256 hash of the verifier, encoded as URL-safe
    /// base64 without padding.
    ///
    /// - Parameter verifier: The code verifier string.
    /// - Returns: The URL-safe base64 encoded SHA256 hash.
    private static func generateS256Challenge(from verifier: String) -> String {
        return sha256(verifier).urlSafeBase64EncodedString()
    }

    /// Computes the SHA256 hash of a string.
    ///
    /// - Parameter input: The input string to hash.
    /// - Returns: The SHA256 hash as Data.
    private static func sha256(_ input: String) -> Data {
        guard let data = input.data(using: .utf8) else {
            Self.logger.error("Failed to encode string as UTF-8 for SHA256")
            return Data()
        }

        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }

        return Data(hash)
    }
}

// MARK: - Data Extension for URL-Safe Base64

extension Data {
    /// Encodes the data as a URL-safe base64 string without padding.
    ///
    /// This encoding is used for PKCE code verifiers and challenges.
    /// It replaces '+' with '-' and '/' with '_', and removes any '=' padding.
    ///
    /// - Returns: A URL-safe base64 encoded string.
    func urlSafeBase64EncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes a URL-safe base64 string to Data.
    ///
    /// This handles the PKCE encoding where '+' and '/' are replaced
    /// and padding may be missing.
    ///
    /// - Parameter string: The URL-safe base64 encoded string.
    /// - Returns: The decoded Data, or nil if decoding fails.
    static func fromURLSafeBase64(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        return Data(base64Encoded: base64)
    }
}

// MARK: - OAuthConfig Extension

extension OAuthConfig {
    /// Generates PKCE parameters for this OAuth configuration.
    ///
    /// - Parameter method: The challenge method to use (defaults to S256).
    /// - Returns: A new `PKCE` instance ready for use in the OAuth flow.
    public func generatePKCE(method: PKCE.ChallengeMethod = .s256) -> PKCE {
        return PKCE.generate(method: method)
    }

    /// Builds the authorization URL with PKCE parameters.
    ///
    /// - Parameters:
    ///   - pkce: The PKCE parameters to include.
    ///   - state: State parameter for CSRF protection.
    /// - Returns: The complete authorization URL.
    public func authorizationURL(pkce: PKCE, state: String) -> URL? {
        var components = URLComponents(url: authorizeURLValue, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: effectiveRedirectURI),
            URLQueryItem(name: "response_type", value: responseType),
            URLQueryItem(name: "state", value: state)
        ]

        // Add PKCE parameters
        if usePKCE {
            queryItems.append(URLQueryItem(name: "code_challenge", value: pkce.codeChallenge))
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: pkce.codeChallengeMethod))
        }

        if !scopes.isEmpty {
            queryItems.append(URLQueryItem(name: "scope", value: scopeString))
        }

        // Add any additional parameters
        if let additionalParams = additionalParameters {
            for (key, value) in additionalParams {
                queryItems.append(URLQueryItem(name: key, value: value))
            }
        }

        components?.queryItems = queryItems
        return components?.url
    }
}
