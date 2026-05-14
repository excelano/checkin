// SpeechService.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Speech
import AVFoundation
import os

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

/// Apple-backed implementation per D9. Configures `SFSpeechRecognizer` with
/// `requiresOnDeviceRecognition = true`, drives the buffer feed off the
/// audio engine input tap, primes recognition with `contextualStrings`,
/// and configures `AVAudioSession` `.playAndRecord` with `.voiceChat` mode
/// for echo cancellation and barge-in per D8.
///
/// Custom language model attachment (D10) is wired in a later slice.
final class AppleSpeechService: SpeechService {
    let transcripts: AsyncStream<TranscriptUpdate>
    private let continuation: AsyncStream<TranscriptUpdate>.Continuation

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private let logger = Logger(subsystem: "com.excelano.checkin", category: "speech")

    private(set) var isListening: Bool = false

    init() {
        self.recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        let (stream, continuation) = AsyncStream<TranscriptUpdate>.makeStream()
        self.transcripts = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func requestAuthorization() async -> SpeechAuthorization {
        guard recognizer != nil else { return .localeNotSupported }

        let speechStatus = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }

        switch speechStatus {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        case .authorized: break
        @unknown default: return .notDetermined
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        return micGranted ? .authorized : .denied
    }

    func startListening(contextualStrings: [String]) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechServiceError.recognizerUnavailable
        }

        // Tear down any prior session before starting a fresh one.
        teardown()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("audio session setup failed: \(error.localizedDescription, privacy: .public)")
            throw SpeechServiceError.audioSessionUnavailable
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        req.contextualStrings = contextualStrings
        self.request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        // The recognition handler runs off the main actor. The continuation
        // and logger are thread-safe to call from any context; cleanup that
        // touches `self` hops back to MainActor via Task.
        let continuation = self.continuation
        let logger = self.logger
        self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            if let result {
                continuation.yield(TranscriptUpdate(
                    text: result.bestTranscription.formattedString,
                    isFinal: result.isFinal
                ))
                if result.isFinal {
                    Task { @MainActor [weak self] in self?.teardown() }
                }
            }
            if let error {
                logger.error("recognition error: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in self?.teardown() }
            }
        }

        isListening = true
    }

    func stopListening() {
        // End audio; the recognizer finalizes and delivers the final result.
        // Cleanup fires from the result handler.
        request?.endAudio()
    }

    func cancel() {
        task?.cancel()
        teardown()
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        task = nil
        request = nil
        isListening = false
    }
}

/// No-op stub for previews, unit tests, and the Phase 5 spine build before
/// `AppleSpeechService` is implemented. Returns `.notDetermined` from
/// authorization, never yields transcripts, silently accepts start/stop/cancel.
final class StubSpeechService: SpeechService {
    let transcripts: AsyncStream<TranscriptUpdate>
    private let continuation: AsyncStream<TranscriptUpdate>.Continuation

    var isListening: Bool { false }

    init() {
        let (stream, continuation) = AsyncStream<TranscriptUpdate>.makeStream()
        self.transcripts = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func requestAuthorization() async -> SpeechAuthorization { .notDetermined }
    func startListening(contextualStrings: [String]) throws {}
    func stopListening() {}
    func cancel() {}
}
