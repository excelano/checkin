// StateMachine.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import Observation
import os

/// State machine spine. `currentState` and `context` are observable so
/// SwiftUI re-renders on transition. Mutators are the only public entry
/// points; direct property writes are not allowed.
@Observable
final class StateMachine {

    private(set) var currentState: DialogState = .signedOut
    private(set) var context: DialogContext = DialogContext()

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin", category: "state")

    func transition(to newState: DialogState) {
        let from = currentState
        currentState = newState
        log(from: from, to: newState)
    }

    func updateContext(_ mutate: (inout DialogContext) -> Void) {
        mutate(&context)
    }

    func resetContext() {
        context = DialogContext()
    }

    private func log(from: DialogState, to: DialogState) {
        #if DEBUG
        logger.debug("transition: \(String(describing: from)) -> \(String(describing: to))")
        print("[state] \(from) -> \(to)")
        #endif
    }
}
