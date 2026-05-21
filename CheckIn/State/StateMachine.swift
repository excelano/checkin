// StateMachine.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Observation
import os

/// State machine spine. `currentState` and `context` are observable so
/// SwiftUI re-renders automatically. Mutators are the only public entry
/// points; direct property writes are not allowed.
@Observable
final class StateMachine {

    private(set) var currentState: DialogState = .signedOut
    private(set) var context: DialogContext = DialogContext()

    /// Unidirectional event log of every transition. The single subscriber
    /// is `SessionCoordinator`, which translates transitions into service
    /// side effects so the state machine stays free of consumer dependencies.
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

    func resetContext() {
        context = DialogContext()
    }

    /// The rest state to return to from speaking, help, or settings.
    /// Driven by listening mode (tap-to-talk → `.idle`, conversation → `.listening`).
    var preferredRestState: RestState = .idle

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
