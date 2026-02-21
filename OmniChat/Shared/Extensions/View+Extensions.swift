//
//  View+Extensions.swift
//  OmniChat
//
//  SwiftUI View utility extensions.
//

import SwiftUI

extension View {
    /// Applies dense spacing modifier for Raycast-style UI.
    func denseSpacing() -> some View {
        self.padding(.vertical, Constants.UI.denseSpacing)
    }
}
