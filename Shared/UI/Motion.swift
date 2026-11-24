import SwiftUI

/// The app's motion vocabulary. With Reduce Motion on, springs and slides
/// become plain cross-fades.
enum Motion {
    /// Default: response ≈ 0.3 s, damping ≈ 0.85, no wobble.
    static func spring(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.85)
    }

    /// A drop settling into place: ≈ 0.3 s, critically damped (no overshoot).
    static func settle(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 1)
    }

    static let hover = Animation.easeOut(duration: 0.12)
    /// A card's fill cross-fading to its new column's tint.
    static let tint = Animation.easeInOut(duration: 0.25)
    static let glowFade = Animation.easeOut(duration: 0.9)

    static func cardTransition(_ reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity)
    }
}

enum BoardSpace {
    /// The board's visible area: card frames, the drag overlay and pointer
    /// positions all use this coordinate space.
    static let viewport = "boardViewport"
}
