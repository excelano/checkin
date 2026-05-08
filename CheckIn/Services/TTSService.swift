// TTSService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Text-to-speech surface backing the `speaking` state. The protocol seam
/// lets previews and tests wire a no-op mock without booting
/// `AVSpeechSynthesizer`.
///
/// The real implementation in `AppleTTSService` uses `AVSpeechSynthesizer`
/// with a locale-matched voice (en-GB device gets a British voice), tracks
/// word-boundary callbacks so D8 barge-in can cut cleanly at a word break,
/// and respects the audio session configuration owned by `SpeechService`.
protocol TTSService: AnyObject {
    var isSpeaking: Bool { get }
    var events: AsyncStream<TTSEvent> { get }

    func speak(_ text: String) throws
    func stop()
    func pause()
    func resume()
}

enum TTSEvent: Equatable {
    case started
    case wordBoundary(charIndex: Int)
    case paused
    case resumed
    case finished
    case cancelled
}

enum TTSServiceError: Error {
    case audioSessionUnavailable
    case synthesizerUnavailable
}

/// Apple-backed implementation. Body lands in Phase 3.
final class AppleTTSService: TTSService {
    var isSpeaking: Bool {
        fatalError("Phase 3: implement with AVSpeechSynthesizer")
    }

    var events: AsyncStream<TTSEvent> {
        fatalError("Phase 3: stream from AVSpeechSynthesizerDelegate")
    }

    func speak(_ text: String) throws {
        fatalError("Phase 3: AVSpeechUtterance with locale-matched voice")
    }

    func stop() {
        fatalError("Phase 3: stopSpeaking(at: .word)")
    }

    func pause() {
        fatalError("Phase 3: pauseSpeaking(at: .word)")
    }

    func resume() {
        fatalError("Phase 3: continueSpeaking()")
    }
}
