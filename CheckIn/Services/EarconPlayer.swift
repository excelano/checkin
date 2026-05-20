// EarconPlayer.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import AVFoundation
import os

/// Plays the short earcons defined in `Sounds/`. The state machine fires
/// these on entry to `active.listening` and `active.processing` per
/// STATES.md.
///
/// Files are bundle resources; the real implementation in
/// `AppleEarconPlayer` uses `AVAudioPlayer` against the audio session
/// owned by `SpeechService`.
protocol EarconPlayer: AnyObject {
    func play(_ earcon: Earcon)
}

enum Earcon: String, CaseIterable {
    case listening
    case thinking

    /// Bundle resource name without extension. Mirrors the filenames in
    /// `CheckIn/Sounds/`.
    var resourceName: String { rawValue }
    var fileExtension: String { "wav" }
}

/// `AVAudioPlayer`-backed earcon playback. Players are constructed once at
/// init and reused for each play; `currentTime = 0` lets the same earcon
/// re-trigger if it fires twice in quick succession. The audio session is
/// the shared session `SpeechService` configures; this class does not
/// touch the session.
final class AppleEarconPlayer: EarconPlayer {
    private var players: [Earcon: AVAudioPlayer] = [:]
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "earcon")

    init() {
        for earcon in Earcon.allCases {
            guard let url = Bundle.main.url(forResource: earcon.resourceName,
                                            withExtension: earcon.fileExtension) else {
                logger.error("earcon missing from bundle: \(earcon.rawValue, privacy: .public)")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[earcon] = player
            } catch {
                logger.error("earcon load failed for \(earcon.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func play(_ earcon: Earcon) {
        guard let player = players[earcon] else {
            logger.error("earcon not loaded: \(earcon.rawValue, privacy: .public)")
            return
        }
        player.currentTime = 0
        player.play()
    }
}

/// Test/preview stub: records calls but plays nothing.
final class StubEarconPlayer: EarconPlayer {
    private(set) var played: [Earcon] = []
    func play(_ earcon: Earcon) {
        played.append(earcon)
    }
}
