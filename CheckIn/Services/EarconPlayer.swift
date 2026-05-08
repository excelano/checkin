// EarconPlayer.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Plays the three short earcons defined in `Sounds/`. The state machine
/// fires these on entry to `active.listening`, `active.processing`, and
/// `active.confirming` respectively per STATES.md and D13.
///
/// All three files are bundle resources; the real implementation in
/// `AppleEarconPlayer` uses `AVAudioPlayer` against the audio session
/// owned by `SpeechService`.
protocol EarconPlayer: AnyObject {
    func play(_ earcon: Earcon)
}

enum Earcon: String, CaseIterable {
    case listening
    case thinking
    case confirmation

    /// Bundle resource name without extension. Mirrors the filenames in
    /// `CheckIn/Sounds/`.
    var resourceName: String { rawValue }
    var fileExtension: String { "wav" }
}

final class AppleEarconPlayer: EarconPlayer {
    func play(_ earcon: Earcon) {
        fatalError("Phase 3: AVAudioPlayer against the SpeechService audio session")
    }
}

/// Test/preview stub: records calls but plays nothing.
final class StubEarconPlayer: EarconPlayer {
    private(set) var played: [Earcon] = []
    func play(_ earcon: Earcon) {
        played.append(earcon)
    }
}
