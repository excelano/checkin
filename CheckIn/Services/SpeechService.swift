// SpeechService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// On-device speech recognition per D9. The protocol seam exists so Phase 4
/// SwiftUI previews and unit tests can wire a deterministic mock without
/// touching the microphone or `SFSpeechRecognizer`.
///
/// The real implementation in `AppleSpeechService` configures
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`, drives
/// VAD off the audio engine input tap, primes recognition with
/// `contextualStrings` from the current summary's senders, subjects, and
/// chat topics, and configures `AVAudioSession` `.playAndRecord` with
/// `.voiceChat` mode for echo cancellation and barge-in per D8.
protocol SpeechService: AnyObject {
    var isListening: Bool { get }
    var transcripts: AsyncStream<TranscriptUpdate> { get }

    func requestAuthorization() async -> SpeechAuthorization
    func startListening(contextualStrings: [String]) throws
    func stopListening()
    func cancel()
}

struct TranscriptUpdate: Equatable {
    let text: String
    let isFinal: Bool
}

enum SpeechAuthorization: Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined
    case localeNotSupported
}

enum SpeechServiceError: Error {
    case notAuthorized
    case audioSessionUnavailable
    case recognizerUnavailable
    case localeNotSupported
}

/// Apple-backed implementation. Body lands in Phase 3 once the Mac Mini
/// is online; the symbol exists now so call sites compile against the
/// production type.
final class AppleSpeechService: SpeechService {
    var isListening: Bool {
        fatalError("Phase 3: implement with SFSpeechRecognizer")
    }

    var transcripts: AsyncStream<TranscriptUpdate> {
        fatalError("Phase 3: stream from SFSpeechRecognitionTask delegate")
    }

    func requestAuthorization() async -> SpeechAuthorization {
        fatalError("Phase 3: SFSpeechRecognizer.requestAuthorization + AVAudioApplication.requestRecordPermission")
    }

    func startListening(contextualStrings: [String]) throws {
        fatalError("Phase 3: configure SFSpeechRecognitionRequest with requiresOnDeviceRecognition = true and contextualStrings")
    }

    func stopListening() {
        fatalError("Phase 3: end audio engine input tap, finalize task")
    }

    func cancel() {
        fatalError("Phase 3: cancel current recognition task")
    }
}
