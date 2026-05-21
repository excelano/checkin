// TTSService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import AVFoundation
import os

/// Text-to-speech surface backing the `speaking` state. The protocol seam
/// lets previews and tests wire a no-op mock without booting
/// `AVSpeechSynthesizer`.
///
/// The real implementation in `AppleTTSService` uses `AVSpeechSynthesizer`
/// with a locale-matched voice (en-GB device gets a British voice) and
/// builds a fresh synthesizer per utterance. The per-utterance recreation
/// is deliberate: an in-flight `AVSpeechSynthesizer` wedges for the rest of
/// the session if the audio session category changes mid-utterance, so a
/// short-lived synth limits the blast radius to a single utterance worst
/// case. `AudioSessionController` owns category transitions.
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

/// Apple-backed implementation per the TTSService doc comment.
///
/// `AVSpeechSynthesizer.delegate` is a weak reference, so this class is the
/// delegate directly rather than wrapping one. NSObject inheritance is the
/// minimum needed for `AVSpeechSynthesizerDelegate` conformance.
///
/// Each call to `speak` builds a fresh `AVSpeechSynthesizer`. The previous
/// instance (if any) is cancelled first. `AudioSessionController` is
/// responsible for setting the right session category before `speak` is
/// called.
final class AppleTTSService: NSObject, TTSService {
    let events: AsyncStream<TTSEvent>
    private let continuation: AsyncStream<TTSEvent>.Continuation

    private var currentSynth: AVSpeechSynthesizer?
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "tts")

    var isSpeaking: Bool { currentSynth?.isSpeaking ?? false }

    override init() {
        let (stream, continuation) = AsyncStream<TTSEvent>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = continuation
        super.init()
    }

    deinit {
        continuation.finish()
    }

    func speak(_ text: String) throws {
        // Drop any in-flight synth before constructing a new one. The old
        // instance is released when the local reference goes out of scope.
        if let prior = currentSynth, prior.isSpeaking {
            prior.stopSpeaking(at: .immediate)
        }

        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        currentSynth = synth

        let utterance = AVSpeechUtterance(string: text)

        // Voice and rate are read fresh from UserDefaults on every utterance.
        // `@AppStorage` in `SettingsView` writes the same keys; reading here
        // means the next utterance picks up changes without an observer.
        let defaults = UserDefaults.standard
        let voiceIdentifier = defaults.string(forKey: AppStorageKey.voiceIdentifier) ?? ""
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        // `UserDefaults.double(forKey:)` returns 0 when the key is absent,
        // which is below `AVSpeechUtteranceMinimumSpeechRate`. Treat 0 as
        // "user hasn't touched the slider yet" and leave the utterance's
        // default rate in place.
        let storedRate = defaults.double(forKey: AppStorageKey.speechRate)
        if storedRate > 0 {
            utterance.rate = Float(storedRate)
        }

        synth.speak(utterance)
    }

    func stop() {
        // `.immediate` so cancellation is synchronous; a category swap that
        // follows a stop can't race with a still-finalizing utterance.
        currentSynth?.stopSpeaking(at: .immediate)
    }

    func pause() {
        currentSynth?.pauseSpeaking(at: .word)
    }

    func resume() {
        currentSynth?.continueSpeaking()
    }
}

extension AppleTTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        continuation.yield(.started)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        continuation.yield(.wordBoundary(charIndex: characterRange.location))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didPause utterance: AVSpeechUtterance) {
        continuation.yield(.paused)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didContinue utterance: AVSpeechUtterance) {
        continuation.yield(.resumed)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        continuation.yield(.finished)
        if synthesizer === currentSynth {
            currentSynth = nil
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        continuation.yield(.cancelled)
        if synthesizer === currentSynth {
            currentSynth = nil
        }
    }
}
