// CustomLanguageModelManager.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Speech
import os.log

/// D10 custom language model: opt-in, default off, with informed consent.
/// When the user enables Voice Recognition Tuning in Settings, this
/// manager builds an `SFCustomLanguageModelData` over their M365 contact
/// display names and saves it under app support. The recognizer in
/// `SpeechService` then configures `SFSpeechRecognitionRequest`'s
/// `customizedLanguageModel` against the saved model.
///
/// Off-state recognition (the default) uses `contextualStrings` only;
/// nothing about contacts is read or written. Toggling off clears the
/// model file immediately. Per D9 and D24, model data never leaves the
/// device: model build, save, and use are all local.
@MainActor
final class CustomLanguageModelManager {

    private let userDefaultsKey = "voiceTuningEnabled"
    private let identifier = "com.excelano.checkin.contacts"
    private let modelVersion = "1.0"
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "lm")

    /// Whether the user has enabled the custom language model. Mirrors
    /// the @AppStorage("voiceTuningEnabled") value in Settings UI.
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    /// URL of the saved custom model under the app support directory.
    /// Build writes here; prepare reads from here; clear deletes here.
    private var modelURL: URL? {
        guard let supportDir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return supportDir.appendingPathComponent("contacts.bin")
    }

    /// Build a custom language model from the supplied display names.
    /// Each contact is phrased as a single token weighted equally; the
    /// recognizer biases toward these names in subsequent recognition
    /// requests. Call this from Settings after the user toggles the
    /// feature on; bodies-of-work are not part of the model.
    func buildModel(from displayNames: [String]) async throws {
        guard !displayNames.isEmpty, let modelURL else {
            logger.error("buildModel called with empty contacts or no model URL; skipping")
            return
        }

        let data = SFCustomLanguageModelData(
            locale: Locale(identifier: "en-US"),
            identifier: identifier,
            version: modelVersion
        ) {
            for name in displayNames {
                SFCustomLanguageModelData.PhraseCount(phrase: name, count: 100)
            }
        }

        try await data.export(to: modelURL)
        logger.info("Built custom language model with \(displayNames.count) contacts")
    }

    /// Prepare the saved model for use by the recognizer. Returns the
    /// configuration `SpeechService` attaches to its `SFSpeechRecognitionRequest`.
    /// Returns nil when the feature is off, no model has been built, or
    /// preparation fails.
    func prepareConfiguration() async -> SFSpeechLanguageModel.Configuration? {
        guard isEnabled, let modelURL,
              FileManager.default.fileExists(atPath: modelURL.path) else {
            return nil
        }

        let configuration = SFSpeechLanguageModel.Configuration(languageModel: modelURL)
        do {
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                for: modelURL,
                clientIdentifier: identifier,
                configuration: configuration
            )
            return configuration
        } catch {
            logger.error("Failed to prepare custom language model: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Toggle on. Builds the model from the supplied contact list and
    /// flips the @AppStorage flag. Toggle off (`disable()`) clears
    /// the saved model and flips the flag back.
    func enable(with displayNames: [String]) async throws {
        try await buildModel(from: displayNames)
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    /// Toggle off. Clears the saved model and flips the flag. Idempotent.
    func disable() {
        UserDefaults.standard.set(false, forKey: userDefaultsKey)
        clearModel()
    }

    /// Remove the saved model file from disk. Called on disable, on
    /// enable rebuild, and any time the user clears the data.
    func clearModel() {
        guard let modelURL,
              FileManager.default.fileExists(atPath: modelURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: modelURL)
            logger.info("Cleared custom language model")
        } catch {
            logger.error("Failed to clear custom language model: \(error.localizedDescription, privacy: .public)")
        }
    }
}
