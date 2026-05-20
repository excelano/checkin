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
/// `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` and drives
/// VAD off the audio engine input tap. `AudioSessionController` owns the
/// audio session category transitions; this service starts/stops the engine
/// and recognizer only.
protocol SpeechService: AnyObject {
    var isListening: Bool { get }
    var transcripts: AsyncStream<TranscriptUpdate> { get }

    func requestAuthorization() async -> SpeechAuthorization
    func startListening() throws
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
/// `requiresOnDeviceRecognition = true` and drives the buffer feed off the
/// audio engine input tap. `AudioSessionController` configures the session
/// before this service is asked to start.
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

    func startListening() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechServiceError.recognizerUnavailable
        }

        // Tear down any prior session before starting a fresh one. The
        // audio session category is owned by `AudioSessionController`; the
        // caller has already configured it to `.listening` by the time we
        // get here.
        teardown()

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.requiresOnDeviceRecognition = true
        req.shouldReportPartialResults = true
        self.request = req

        let inputNode = audioEngine.inputNode
        // Defensive: remove any leftover tap from a prior session whose
        // teardown raced with an external engine stop. Idempotent if no
        // tap is installed.
        inputNode.removeTap(onBus: 0)
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
        }
        // Always remove the tap, not gated on isRunning. A category swap
        // by `AudioSessionController` can stop the engine externally before
        // this runs, leaving a stale tap that breaks the next installTap
        // call with "input node already has a tap installed".
        audioEngine.inputNode.removeTap(onBus: 0)
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
    func startListening() throws {}
    func stopListening() {}
    func cancel() {}
}
