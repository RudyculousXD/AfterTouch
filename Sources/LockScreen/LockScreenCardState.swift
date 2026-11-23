import Foundation
import Observation

/// Shared between the SwiftUI card and the panel hosting it.
///
/// The view toggles `isExpanded`; `LockScreenPanel` reads it to decide which pixels are
/// interactive, because the panel is sized to the expanded card and everything outside the
/// card's current rect must stay click-through. Keeping the flag here rather than in `@State`
/// is what lets AppKit ask the question at hit-test time.
@MainActor
@Observable
final class LockScreenCardState {
    var isExpanded = true
    var showsLyrics = false

    /// Called when the panel is hidden, so an unlock never leaves the card expanded for the
    /// next lock.
    func collapse() {
        isExpanded = true
        showsLyrics = false
    }
}
