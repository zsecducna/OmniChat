//
//  Date+Extensions.swift
//  OmniChat
//
//  Date formatting and utility extensions.
//

import Foundation

extension Date {
    /// Returns a relative time string (e.g., "2m ago", "Yesterday").
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
