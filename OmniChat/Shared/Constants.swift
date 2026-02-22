//
//  Constants.swift
//  OmniChat
//
//  Global constants for the application.
//

import Foundation

/// Application-wide constants.
enum Constants {
    /// Bundle identifier components.
    enum BundleID {
        static let base = "com.zsec.omnichat"
        static let iCloud = "iCloud.com.zsec.omnichat"
        static let shared = "com.zsec.omnichat.shared"
    }

    /// API configuration defaults.
    enum API {
        static let defaultTimeout: TimeInterval = 60
        static let maxRetries = 3
    }

    /// UI configuration.
    enum UI {
        static let denseSpacing: CGFloat = 4
        static let messageSpacing: CGFloat = 6
    }
}
