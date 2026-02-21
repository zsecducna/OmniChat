//
//  String+Extensions.swift
//  OmniChat
//
//  String utility extensions.
//

import Foundation

extension String {
    /// Truncates the string to a maximum length with ellipsis.
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength { return self }
        return String(prefix(maxLength)) + "..."
    }
}
