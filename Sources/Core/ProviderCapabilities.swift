import Foundation

/// What a given provider can actually do.
///
/// The UI reads this to disable controls a provider genuinely lacks, so we never render a
/// button that silently does nothing. The differences are real, not hypothetical: Spotify has
/// no `mute` property at all, and its `starred` is read-only.
struct ProviderCapabilities: OptionSet {
    let rawValue: Int

    static let seek           = ProviderCapabilities(rawValue: 1 << 0)
    static let volume         = ProviderCapabilities(rawValue: 1 << 1)
    /// The app has a real mute property. Without this, mute is emulated by saving and
    /// restoring the previous volume.
    static let nativeMute     = ProviderCapabilities(rawValue: 1 << 2)
    static let shuffle        = ProviderCapabilities(rawValue: 1 << 3)
    static let repeatMode     = ProviderCapabilities(rawValue: 1 << 4)
    /// Repeat has a distinct *one* state, so the control cycles through three positions.
    /// Spotify's scripting dictionary exposes `repeating` as a plain boolean — verified
    /// 2026-08-21 against the shipping build — so for Spotify the cycle is off/all only.
    static let repeatOne      = ProviderCapabilities(rawValue: 1 << 6)
    /// Favourite/like can be *written*. Reading it may still be possible without this.
    static let favorite       = ProviderCapabilities(rawValue: 1 << 5)
}
