// FileUtteranceLog.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

#if DEBUG

import Foundation
import os

/// JSONL log of classified utterances written to the app's Application
/// Support directory. One line per turn: timestamp, utterance text,
/// chosen intent, confidence, top-5 ranked candidates with distances,
/// response text, and category.
///
/// The file is excluded from iCloud and iTunes/Finder backups so the
/// data never leaves the device through Apple's backup pipeline. Pull
/// it off-device for review with:
///
///   xcrun devicectl device copy from --device <id> \
///       --domain-type appDataContainer \
///       --domain-identifier com.excelano.checkin \
///       --source 'Library/Application Support/utterance-log.jsonl' \
///       --destination ~/utterance-log.jsonl
///
/// Debug-only. Release builds use `NoOpUtteranceLog`.
final class FileUtteranceLog: UtteranceLog {
    private let url: URL
    private let logger = Logger(subsystem: "com.excelano.checkin", category: "utterance-log")
    private let encoder: JSONEncoder

    init() {
        let fm = FileManager.default
        let supportDir = (try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true))
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.url = supportDir.appendingPathComponent("utterance-log.jsonl")
        let enc = JSONEncoder()
        enc.outputFormatting = []
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
    }

    func record(utterance: String,
                classified: ClassifiedIntent,
                ranking: [IntentRanking],
                response: SpokenResponse) async {
        let rec = Record(
            ts: Date(),
            utterance: utterance,
            intent: encodeIntent(classified.intent),
            confidence: classified.confidence,
            ranking: ranking.prefix(5).map {
                RankedIntentRecord(intent: encodeIntent($0.intent), distance: $0.distance)
            },
            response: response.text,
            category: encodeCategory(response.category)
        )
        do {
            var line = try encoder.encode(rec)
            line.append(0x0A)
            try append(line)
        } catch {
            logger.error("encode/append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func append(_ data: Data) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
            var u = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? u.setResourceValues(values)
        }
    }
}

private struct Record: Encodable {
    let ts: Date
    let utterance: String
    let intent: String
    let confidence: Double
    let ranking: [RankedIntentRecord]
    let response: String
    let category: String
}

private struct RankedIntentRecord: Encodable {
    let intent: String
    let distance: Double
}

private func encodeIntent(_ intent: Intent) -> String {
    switch intent {
    case .summary: return "summary"
    case .filter: return "filter"
    case .refresh: return "refresh"
    case .repeatLast: return "repeatLast"
    case .stop: return "stop"
    case .help: return "help"
    case .open: return "open"
    case .reply: return "reply"
    case .join: return "join"
    case .timeQuery: return "timeQuery"
    case .exit: return "exit"
    case .settings: return "settings"
    case .yes: return "yes"
    case .no: return "no"
    case .ordinalSelection: return "ordinalSelection"
    case .markRead: return "markRead"
    case .flag: return "flag"
    case .delete: return "delete"
    case .inScopeUnsupported(let kind):
        switch kind {
        case .readContent: return "inScopeUnsupported.readContent"
        case .summarizeContent: return "inScopeUnsupported.summarizeContent"
        case .analyzeContent: return "inScopeUnsupported.analyzeContent"
        case .voiceReply: return "inScopeUnsupported.voiceReply"
        case .listBrowse: return "inScopeUnsupported.listBrowse"
        }
    case .outOfScope: return "outOfScope"
    case .unknown: return "unknown"
    }
}

private func encodeCategory(_ category: ResponseCategory) -> String {
    switch category {
    case .summary: return "summary"
    case .answer: return "answer"
    case .refusal: return "refusal"
    case .redirect: return "redirect"
    case .disambiguation: return "disambiguation"
    case .confirmation: return "confirmation"
    case .error: return "error"
    case .help: return "help"
    case .latencyReassurance: return "latencyReassurance"
    }
}

#endif
