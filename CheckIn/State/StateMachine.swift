// StateMachine.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Observation
import os

/// The hierarchical state machine spine per D1 and D33.
///
/// Voice and touch both transition through a single source of truth.
/// `currentState` and `context` are observable so SwiftUI views in Phase 4
/// re-render automatically. Mutators are the only public entry points;
/// direct property writes are not allowed.
@Observable
final class StateMachine {

    private(set) var currentState: DialogState = .signedOut
    private(set) var context: DialogContext = DialogContext()

    /// Unidirectional event log of every transition. The single subscriber
    /// is `SessionCoordinator`, which translates transitions into service
    /// side effects (start listening, fetch summary, speak, etc.) so the
    /// state machine stays free of consumer dependencies.
    @ObservationIgnored let transitions: AsyncStream<TransitionEvent>
    @ObservationIgnored private let transitionContinuation: AsyncStream<TransitionEvent>.Continuation

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin", category: "state")

    init() {
        let (stream, continuation) = AsyncStream<TransitionEvent>.makeStream(bufferingPolicy: .unbounded)
        self.transitions = stream
        self.transitionContinuation = continuation
    }

    deinit {
        transitionContinuation.finish()
    }

    func transition(to newState: DialogState) {
        let from = currentState
        currentState = newState
        transitionContinuation.yield(TransitionEvent(from: from, to: newState))
        log(from: from, to: newState)
    }

    func updateContext(_ mutate: (inout DialogContext) -> Void) {
        mutate(&context)
    }

    func recordTurn(user: String, system: String, category: ResponseCategory) {
        context.recordTurn(user: user, system: system)
        context.rememberPhrasing(system, in: category)
    }

    func resetContext() {
        context = DialogContext()
    }

    /// The rest state to return to from speaking, help, or settings. Driven
    /// by listening mode (D17). Set by the listening-mode setting at sign-in
    /// and on mode changes; defaults to tap-to-talk.
    var preferredRestState: RestState = .idle

    /// Coordinator hooks the view layer calls when the user resolves or
    /// cancels a disambiguation. The SwiftUI panel only has a reference to
    /// the state machine, not the coordinator, so the coordinator wires
    /// these on `start()` to route panel events back to its own logic
    /// without a singleton or a back-pointer through the view tree.
    @ObservationIgnored var onCandidateSelected: ((Candidate) -> Void)?
    @ObservationIgnored var onDisambiguationCancelled: (() -> Void)?

    private func log(from: DialogState, to: DialogState) {
        #if DEBUG
        logger.debug("transition: \(String(describing: from)) -> \(String(describing: to))")
        #endif
    }
}

/// A single state transition emitted on `StateMachine.transitions`.
struct TransitionEvent: Equatable {
    let from: DialogState
    let to: DialogState
}
