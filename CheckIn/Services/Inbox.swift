// Inbox.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UserNotifications
import WidgetKit
import os

@MainActor @Observable
final class Inbox {
    private(set) var summary: CheckInSummary?
    /// User preference: true to lift the 20-newest cap and fetch everything
    /// (capped at 999 to stay under Graph's `$top` ceiling of 1000).
    /// Persisted across launches.
    private(set) var showingAllEmails: Bool
    /// True if the most recent refresh (full or partial) hit at least one
    /// Graph error. Cleared by the next successful full refresh. Drives
    /// the orange warning banner in the summary view.
    private(set) var lastRefreshFailed: Bool = false
    /// Most-recent reversible bulk action. Set by each bulk method, drives
    /// the floating "Undo" banner in the summary view. Auto-clears after
    /// 8 seconds; only one is held at a time (replaced by the next bulk
    /// action). Nil when there's nothing to undo.
    private(set) var pendingUndo: UndoableBulkAction?
    /// Transient user-facing failure message, set when an optimistic
    /// action reverted because Graph rejected it. Drives a floating
    /// banner in the summary view. Auto-clears after 6 seconds; the
    /// most recent failure replaces any earlier one. Used only for
    /// high-consequence actions where the silent revert isn't enough —
    /// currently OOO toggle and custom status message. Nil when there's
    /// no failure to surface.
    private(set) var transientError: String?
    /// True when the user's Graph auto-reply status is `alwaysEnabled` or
    /// `scheduled`. Drives the OOO indicator that replaces the presence
    /// glyph and reroutes the tap to Settings. Refreshed on every refresh.
    private(set) var isOutOfOffice: Bool = false
    /// Teams custom status message — the short text that shows under the
    /// user's name in Teams alongside the presence glyph. Empty when
    /// not set. Refreshed on every refresh.
    private(set) var customStatusMessage: String = ""
    /// Current Microsoft 365 presence. Refreshed alongside the rest of the
    /// summary; `setPresence(_:)` updates it optimistically and confirms
    /// with the server. `.unknown` before the first successful fetch,
    /// after sign-out, or when Teams is disabled.
    private(set) var currentPresence: Presence = .unknown
    // MARK: - Unified meeting store
    //
    // Every Meeting CheckIn knows about lives in `meetingsById`. The
    // three index structures below tell the UI/conflict-detector which
    // role each meeting plays (today's window, an invite-email
    // referent, or the future-range reference pool). The `nextMeeting`,
    // `laterToday`, `inviteMeetings`, and `conflictReferenceMeetings`
    // accessors are pure computed views — there's no shadow state to
    // keep in sync.
    /// Single source of truth for every Meeting value in the session,
    /// keyed by `Meeting.id`. Reads go through here; writes (RSVP edit,
    /// delete, refresh) update here.
    private(set) var meetingsById: [String: Meeting] = [:]
    /// Today's-window meeting ids, ordered by start time. First entry
    /// is the "next meeting" highlighted on the summary card; the rest
    /// are the "Later today" section.
    private(set) var todayMeetingIds: [String] = []
    /// Map from an invite email's id to its underlying meeting id.
    /// Populated by `matchInvitesToCalendar(emails:calendar:)`.
    private(set) var inviteEmailMeetingIds: [String: String] = [:]
    /// Meeting ids in the conflict-detection reference pool — events
    /// from `calendarView` spanning the invite-emails date range.
    private(set) var referenceMeetingIds: Set<String> = []

    /// The "next meeting" card on the summary view. Computed from the
    /// first entry of `todayMeetingIds`.
    var nextMeeting: Meeting? { todayMeetingIds.first.flatMap { meetingsById[$0] } }
    /// The "Later today" list. Computed from `todayMeetingIds` after
    /// the next-meeting one.
    var laterToday: [Meeting] {
        Array(todayMeetingIds.dropFirst()).compactMap { meetingsById[$0] }
    }

    /// Every Meeting CheckIn knows about — today's window, invite
    /// referents, and reference-pool calendar events. Read by
    /// `ConflictResolutionSheet` to build its candidate list, and by
    /// the internal conflict detector. The single source of truth.
    var allKnownMeetings: [Meeting] { Array(meetingsById.values) }

    /// Map from invite email id → its underlying Meeting. Pure
    /// computed view over the email-id index and the master store.
    var inviteMeetings: [String: Meeting] {
        inviteEmailMeetingIds.compactMapValues { meetingsById[$0] }
    }

    /// Plain-calendar events used for conflict detection against
    /// invites whose meetings sit outside today's window. Pure
    /// computed view over the reference-pool index.
    var conflictReferenceMeetings: [Meeting] {
        referenceMeetingIds.compactMap { meetingsById[$0] }
    }

    /// Lookup a Meeting by id across every source. Used by surfaces
    /// outside Inbox (e.g. `ConflictResolutionSheet`) that need to
    /// render the primary meeting and each overlapping candidate
    /// regardless of which bucket they came from.
    func meeting(withId id: String) -> Meeting? { meetingsById[id] }

    private let graphClient: GraphClient
    private let authService: AuthService
    private let teamsEnabled: Bool
    private let meetingNotifications = MeetingNotifications()
    private var didFetchUserID = false
    private var lastRefreshedAt: Date?
    private var didRequestBadgeAuthorization = false
    @ObservationIgnored private var undoExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var transientErrorExpiryTask: Task<Void, Never>?

    private var emailTop: Int { showingAllEmails ? 999 : 20 }

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin", category: "inbox")

    init(graphClient: GraphClient, authService: AuthService, teamsEnabled: Bool) {
        self.graphClient = graphClient
        self.authService = authService
        self.teamsEnabled = teamsEnabled
        self.showingAllEmails = UserDefaults.standard.bool(forKey: AppStorageKey.showingAllEmails)
    }

    /// Drop in-memory state tied to the previous session so the next
    /// refresh starts clean. Called from sign-out — the next user may be
    /// a different account on the same device, so the cached user id,
    /// summary, and any pending failure flag are all stale.
    func reset() {
        summary = nil
        didFetchUserID = false
        lastRefreshedAt = nil
        lastRefreshFailed = false
        pendingUndo = nil
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        transientError = nil
        transientErrorExpiryTask?.cancel()
        transientErrorExpiryTask = nil
        currentPresence = .unknown
        meetingsById = [:]
        todayMeetingIds = []
        inviteEmailMeetingIds = [:]
        referenceMeetingIds = []
        graphClient.clearUser()
    }

    /// Set a fresh undoable action, replacing whatever was there before
    /// and restarting the 8-second auto-expiry timer.
    private func setPendingUndo(_ action: UndoableBulkAction) {
        pendingUndo = action
        undoExpiryTask?.cancel()
        undoExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, !Task.isCancelled else { return }
            self.pendingUndo = nil
        }
    }

    /// User dismissed the undo banner without invoking it.
    func dismissUndo() {
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        pendingUndo = nil
    }

    /// Run the captured undo closure and clear the pending state.
    func performUndo() async {
        guard let action = pendingUndo else { return }
        pendingUndo = nil
        undoExpiryTask?.cancel()
        undoExpiryTask = nil
        await action.undo()
    }

    /// Surface a brief failure message for an optimistic action that
    /// reverted. Replaces any earlier message and restarts the 6-second
    /// auto-clear timer.
    private func showTransientError(_ message: String) {
        transientError = message
        transientErrorExpiryTask?.cancel()
        transientErrorExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled else { return }
            self.transientError = nil
        }
    }

    /// User dismissed the transient-error banner without waiting for
    /// the auto-clear.
    func dismissTransientError() {
        transientErrorExpiryTask?.cancel()
        transientErrorExpiryTask = nil
        transientError = nil
    }

    /// Toggle the email cap and refetch just the emails. No need to ripple
    /// meeting/chat updates.
    func setShowingAllEmails(_ show: Bool) async {
        guard show != showingAllEmails else { return }
        showingAllEmails = show
        UserDefaults.standard.set(show, forKey: AppStorageKey.showingAllEmails)
        let result = await fetchEmails()
        await applyEmailsResult(result)
        if result.failed { lastRefreshFailed = true }
    }

    func refresh() async {
        var anyFailed = false
        // `fetchUserID` powers two features now: Teams pending-chat
        // filtering (only when teamsEnabled) and external-sender
        // detection (always useful). Always fetch on first refresh.
        if !didFetchUserID {
            do {
                try await graphClient.fetchUserID()
                didFetchUserID = true
            } catch {
                logger.error("fetchUserID failed: \(error.localizedDescription, privacy: .public)")
                anyFailed = true
            }
        }
        let userIDReady = didFetchUserID

        // Heartbeat before the presence read, so one refresh reflects Available; reading first left the display a refresh behind on return.
        await refreshPresenceSession()

        async let meetingsT = fetchMeetings()
        async let emailsT = fetchEmails()
        async let chatsT = fetchChats(userIDReady: userIDReady)
        async let presenceT = fetchPresence()
        async let oooT = fetchOutOfOffice()
        let meetingsResult = await meetingsT
        let emailsResult = await emailsT
        let (chats, chatsFailed) = await chatsT
        summary = CheckInSummary(emails: emailsResult.emails,
                                 chats: chats,
                                 totalUnreadEmails: emailsResult.totalCount)
        loadTodayMeetings(next: meetingsResult.next, laterToday: meetingsResult.laterToday)
        await rebuildInviteCaches(from: emailsResult.emails)
        let (fetchedPresence, fetchedMessage) = await presenceT
        currentPresence = fetchedPresence
        customStatusMessage = fetchedMessage
        isOutOfOffice = await oooT
        lastRefreshedAt = Date()
        lastRefreshFailed = anyFailed || meetingsResult.failed || emailsResult.failed || chatsFailed
        await updateAppBadge()
        await rescheduleMeetingNotificationsIfEnabled()
        writeWidgetSnapshot()
    }

    /// Serialize the current summary into the App Group container the
    /// widget reads from, and tell the widget to reload. Widgets can't
    /// authenticate or call Graph themselves, so this is the only way
    /// they get fresh data.
    private func writeWidgetSnapshot() {
        guard let summary else { return }
        let next = nextMeeting
        let snapshot = CheckInSnapshot(
            updatedAt: Date(),
            nextMeetingSubject: next?.subject,
            nextMeetingStart: next?.start,
            nextMeetingOrganizer: next?.organizer,
            nextMeetingJoinUrl: next?.joinUrl,
            unreadEmailCount: summary.totalUnreadEmails,
            chatCount: summary.chats.count
        )
        guard let data = try? JSONEncoder().encode(snapshot),
              let defaults = UserDefaults(suiteName: CheckInSnapshot.appGroupIdentifier) else {
            logger.error("writeWidgetSnapshot: couldn't encode or open App Group defaults")
            return
        }
        defaults.set(data, forKey: CheckInSnapshot.userDefaultsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// sessionId for `/me/presence/setPresence`. Microsoft constrains
    /// delegated-permission callers to set sessionId equal to the
    /// calling app's Azure AD client ID — a random GUID is silently
    /// rejected. We use the effective client ID (custom registration
    /// override if set, otherwise the published one).
    private var presenceSessionId: String {
        Constants.effectiveClientID
    }

    /// Re-up CheckIn's presence session as a pure "I'm here" heartbeat
    /// reporting Available. The preferred (Busy / DND / etc.) is what
    /// gets shown to others — the session just keeps Graph honoring
    /// preferred at all, and keeps the user visible as Available when
    /// no preferred is set (Reset to auto). 1-hour expiration; we renew
    /// on every refresh so it never has a chance to lapse while CheckIn
    /// is in active use.
    private func refreshPresenceSession() async {
        guard teamsEnabled else { return }
        do {
            try await graphClient.setSessionPresence(sessionId: presenceSessionId, presence: .available)
        } catch {
            logger.error("refreshPresenceSession failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read the auto-reply status from Graph. Treats any non-`disabled`
    /// state (alwaysEnabled, scheduled) as "out of office is on" — we
    /// don't model scheduled-with-dates in our UI; the user manages
    /// dates in Outlook web and CheckIn just shows on/off.
    private func fetchOutOfOffice() async -> Bool {
        do {
            let reply = try await graphClient.fetchAutomaticReplies()
            return reply.status != "disabled"
        } catch {
            logger.error("fetchOutOfOffice failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Re-schedule the 1-minute-out meeting alerts from the freshly-fetched
    /// summary. Toggled by the `meetingNotifications` AppStorage flag, so
    /// flipping it off in Settings and refreshing clears any pending alerts.
    private func rescheduleMeetingNotificationsIfEnabled() async {
        let enabled = UserDefaults.standard.bool(forKey: AppStorageKey.meetingNotifications)
        guard enabled, summary != nil else {
            await meetingNotifications.clearAll()
            return
        }
        var meetings: [Meeting] = []
        if let m = nextMeeting { meetings.append(m) }
        meetings.append(contentsOf: laterToday)
        await meetingNotifications.scheduleAll(meetings)
    }

    /// Settings-toggle entry point. Requests notification authorization
    /// (alert + sound). On grant, schedules alerts for the meetings we
    /// already have. Returns the granted state so the caller can flip
    /// the toggle back off if the user declined.
    func enableMeetingNotifications() async -> Bool {
        let granted = await meetingNotifications.requestAuthorization()
        if granted {
            await rescheduleMeetingNotificationsIfEnabled()
        }
        return granted
    }

    /// Drop any pending meeting alerts. Called when the user toggles
    /// the setting off.
    func disableMeetingNotifications() async {
        await meetingNotifications.clearAll()
    }

    /// Default auto-reply text used only when Graph reports an empty
    /// message at toggle-on time. Anything the user has previously set
    /// (via Outlook web, for instance) is preserved.
    private let defaultOutOfOfficeMessage =
        "I'm currently out of the office and will respond when I return."

    /// Set (or clear) the Teams custom status message. Optimistic update
    /// with revert on failure, mirroring the presence pattern.
    func setCustomStatusMessage(_ message: String) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = customStatusMessage
        customStatusMessage = trimmed
        do {
            try await graphClient.setStatusMessage(trimmed)
        } catch {
            logger.error("setCustomStatusMessage failed: \(error.localizedDescription, privacy: .public)")
            customStatusMessage = previous
            showTransientError("Couldn't update your status. Try again.")
        }
    }

    /// Enable auto-replies (`alwaysEnabled` with no end date). Optimistic
    /// UI update with revert on failure, mirroring the presence pattern.
    func setOutOfOffice(_ on: Bool) async {
        let previous = isOutOfOffice
        isOutOfOffice = on
        do {
            if on {
                try await graphClient.enableAutomaticReplies(defaultMessage: defaultOutOfOfficeMessage)
            } else {
                try await graphClient.disableAutomaticReplies()
            }
        } catch {
            logger.error("setOutOfOffice(\(on)) failed: \(error.localizedDescription, privacy: .public)")
            isOutOfOffice = previous
            showTransientError("Couldn't update Out of Office. Try again.")
        }
    }

    /// Set the user-preferred Microsoft 365 presence, or clear it back to
    /// auto-detection when passed `.unknown`. Optimistic UI; reverts on
    /// failure. After a Reset, re-fetches the auto-detected state.
    ///
    /// If the user is currently Out of Office, also turns OOO off —
    /// picking a regular presence state is an explicit signal that the
    /// user is back, and Reset-to-auto means "drop all my overrides".
    /// The OOO toggle and Teams-presence picker live in the same menu
    /// so the mutual exclusion needs to happen here.
    func setPresence(_ presence: Presence) async {
        let previous = currentPresence
        currentPresence = presence
        do {
            // Keep our session alive at Available so Graph honors the
            // preferred override and so Reset-to-auto shows Available
            // (rather than Offline) when no other Microsoft client has
            // a session.
            do {
                try await graphClient.setSessionPresence(sessionId: presenceSessionId, presence: .available)
            } catch {
                logger.error("setPresence session sync failed: \(error.localizedDescription, privacy: .public)")
            }
            if presence == .unknown {
                try await graphClient.clearUserPreferredPresence()
                let (p, msg) = await fetchPresence()
                currentPresence = p
                customStatusMessage = msg
            } else {
                try await graphClient.setUserPreferredPresence(presence)
            }
        } catch {
            logger.error("setPresence(\(presence.displayName, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            currentPresence = previous
        }
        if isOutOfOffice {
            await setOutOfOffice(false)
        }
    }

    /// Sets the iOS app-icon badge to `unread emails + pending chats`. The
    /// first call requests notification permission (badge-only). Silent
    /// no-op if denied. Meetings are intentionally excluded — they're
    /// scheduled, not items to triage.
    private func updateAppBadge() async {
        guard let s = summary else { return }
        let count = s.totalUnreadEmails + s.chats.count
        let center = UNUserNotificationCenter.current()
        if !didRequestBadgeAuthorization {
            didRequestBadgeAuthorization = true
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.badge])
            }
        }
        try? await center.setBadgeCount(count)
    }

    /// Skip the refresh if the last one finished within `threshold` seconds.
    /// Used by the scene-foreground hook so quick app-switches don't trigger
    /// back-to-back Graph fetches.
    func refreshIfStale(threshold: TimeInterval = 30) async {
        if let last = lastRefreshedAt, Date().timeIntervalSince(last) < threshold {
            return
        }
        await refresh()
    }

    /// Mark every visible email read in a single Graph `$batch`. Tops up
    /// from the server afterward if the cap was hiding additional unread.
    func markAllVisibleRead() async {
        let preserved = summary?.emails ?? []
        await runBulkMarkRead(emails: preserved)
    }

    /// Mark the visible emails classified as "Other" by Microsoft's Focused
    /// Inbox ML. Leaves "Focused" emails alone.
    func markOtherInboxRead() async {
        let candidates = (summary?.emails ?? []).filter { $0.inferenceClassification == "other" }
        await runBulkMarkRead(emails: candidates)
    }

    /// Mark meeting cancellations and RSVP responses (the noise that piles
    /// up after the actionable invite). The original `meetingRequest`
    /// invite is left alone — the user might still need to RSVP to it.
    func markMeetingNoticesRead() async {
        let candidates = (summary?.emails ?? []).filter(\.isMeetingNotice)
        await runBulkMarkRead(emails: candidates)
    }

    /// Mark visible emails that look like mailing-list traffic
    /// (RFC 2369 `List-Unsubscribe` header present).
    func markMailingListsRead() async {
        let candidates = (summary?.emails ?? []).filter { $0.isMailingList }
        await runBulkMarkRead(emails: candidates)
    }

    /// Mark visible emails sent from a domain other than the signed-in
    /// user's own. Useful when work-internal mail is the priority and
    /// outside-the-company senders can be dismissed.
    func markExternalSendersRead() async {
        let userDomain = graphClient.userMailDomain
        guard !userDomain.isEmpty else { return }
        let candidates = (summary?.emails ?? []).filter { e in
            guard !e.fromAddress.isEmpty,
                  let atIdx = e.fromAddress.firstIndex(of: "@") else { return false }
            let senderDomain = e.fromAddress[e.fromAddress.index(after: atIdx)...].lowercased()
            return senderDomain != userDomain
        }
        await runBulkMarkRead(emails: candidates)
    }

    /// Exposes the user's mail domain so the view layer can compute the
    /// count for the bulk-actions menu without re-implementing the
    /// fromAddress comparison.
    var userMailDomain: String { graphClient.userMailDomain }

    /// Exposes the user's full mail address so the preview sheet can
    /// filter the signed-in user out of the "also to" recipient list.
    var currentUserMail: String { graphClient.currentUserMail }

    /// Mark every visible email from the given SMTP address as read.
    /// Used by the row-level context menu.
    func markAllFromSenderRead(_ address: String) async {
        guard !address.isEmpty else { return }
        let candidates = (summary?.emails ?? []).filter { $0.fromAddress == address }
        await runBulkMarkRead(emails: candidates)
    }

    /// Flip every read email received today back to unread, so a day's
    /// mail that got cleared elsewhere (Outlook web, another phone)
    /// shows up in CheckIn again. Re-fetches the summary because the
    /// newly-unread emails are not in our visible list.
    func markTodayUnread() async {
        do {
            let ids = try await graphClient.idsOfReadEmailsReceivedToday()
            try await resurfaceAsUnread(ids: ids, summary: "Marked \(ids.count) today unread")
        } catch {
            logger.error("markTodayUnread failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Flip every read, flagged Inbox email back to unread, so follow-up
    /// items that were already read resurface in CheckIn. Same shape as
    /// `markTodayUnread`: the newly-unread emails aren't in the visible
    /// list, so we re-fetch the summary.
    func markFlaggedUnread() async {
        do {
            let ids = try await graphClient.idsOfReadFlaggedEmails()
            try await resurfaceAsUnread(ids: ids, summary: "Marked \(ids.count) flagged unread")
        } catch {
            logger.error("markFlaggedUnread failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shared tail for the "resurface as unread" bulk actions: batch-marks
    /// the given IDs unread, re-fetches the summary (the newly-unread
    /// emails aren't in the visible list), and registers an undo that
    /// re-marks the same IDs read. No-ops on an empty set, so no undo
    /// banner appears when there was nothing to flip.
    private func resurfaceAsUnread(ids: [String], summary label: String) async throws {
        guard !ids.isEmpty else { return }
        _ = try await graphClient.batchMarkUnread(ids: ids)
        let result = await fetchEmails()
        await applyEmailsResult(result)
        if result.failed { lastRefreshFailed = true }
        await updateAppBadge()
        setPendingUndo(UndoableBulkAction(
            summary: label,
            undo: { [weak self] in
                _ = try? await self?.graphClient.batchMarkRead(ids: ids)
                if let self {
                    let r = await self.fetchEmails()
                    await self.applyEmailsResult(r)
                }
                await self?.updateAppBadge()
            }
        ))
    }

    /// Mark every visible email whose normalized subject matches. Strips
    /// Re:/Fwd: prefixes and ignores case, so a thread of replies all
    /// group together. Useful for dismissing a noisy thread or
    /// notification series in one move.
    func markAllWithSubjectRead(_ subject: String) async {
        let key = subject.normalizedSubjectKey
        guard !key.isEmpty else { return }
        let candidates = (summary?.emails ?? []).filter { $0.subject.normalizedSubjectKey == key }
        await runBulkMarkRead(emails: candidates)
    }

    /// Shared entry point for the bulk mark-read variants. Runs the
    /// optimistic mark-read pipeline and, on a non-empty input,
    /// registers an undo that batch-marks the same IDs unread and
    /// refetches the email list.
    private func runBulkMarkRead(emails: [Email]) async {
        guard !emails.isEmpty else { return }
        let ids = emails.map(\.id)
        await performMarkRead(emails: emails)
        setPendingUndo(UndoableBulkAction(
            summary: "Marked \(ids.count) read",
            undo: { [weak self] in
                await self?.undoMarkRead(ids: ids)
            }
        ))
    }

    private func undoMarkRead(ids: [String]) async {
        _ = try? await graphClient.batchMarkUnread(ids: ids)
        let result = await fetchEmails()
        await applyEmailsResult(result)
        if result.failed { lastRefreshFailed = true }
        await updateAppBadge()
    }

    /// Optimistically removes the given emails from the visible list, sends
    /// a single Graph `$batch` PATCH, and re-inserts only the emails that
    /// came back non-2xx. Uses `$batch` rather than fanning concurrent
    /// PATCHes because Graph rate-limits bursts and silently drops some.
    private func performMarkRead(emails: [Email]) async {
        let preserved = emails
        let ids = preserved.map(\.id)
        let idSet = Set(ids)
        guard !idSet.isEmpty else { return }

        summary?.emails.removeAll { idSet.contains($0.id) }
        summary?.totalUnreadEmails -= ids.count
        defer { Task { await updateAppBadge() } }

        do {
            let failed = try await graphClient.batchMarkRead(ids: ids)
            let toRestore = preserved.filter { failed.contains($0.id) }
            if !toRestore.isEmpty {
                summary?.emails.append(contentsOf: toRestore)
                summary?.emails.sort { $0.received > $1.received }
                summary?.totalUnreadEmails += toRestore.count
                logger.error("performMarkRead: \(toRestore.count) of \(ids.count) failed")
            }
            // Top up from the server when there are still-unread emails
            // beyond what we had cached. Otherwise the user is left
            // looking at a shrunken section that pull-to-refresh would fix.
            if let s = summary, s.totalUnreadEmails > s.emails.count {
                let result = await fetchEmails()
                await applyEmailsResult(result)
                if result.failed { lastRefreshFailed = true }
            }
        } catch {
            logger.error("performMarkRead failed: \(error.localizedDescription, privacy: .public)")
            summary?.emails.append(contentsOf: preserved)
            summary?.emails.sort { $0.received > $1.received }
            summary?.totalUnreadEmails += ids.count
        }
    }

    /// Optimistically flips the flag on every visible email not already in
    /// the target state, sends a single Graph `$batch` PATCH, and reverts
    /// only the emails that came back non-2xx. Registers an undo so the
    /// reverse flip can be triggered from the floating banner.
    func setFlaggedAllVisible(_ flagged: Bool) async {
        let targets = (summary?.emails ?? []).filter { $0.isFlagged != flagged }
        let ids = targets.map(\.id)
        guard !ids.isEmpty else { return }

        await batchFlipFlagged(ids: ids, to: flagged)

        setPendingUndo(UndoableBulkAction(
            summary: "\(flagged ? "Flagged" : "Unflagged") \(ids.count)",
            undo: { [weak self] in
                await self?.batchFlipFlagged(ids: ids, to: !flagged)
            }
        ))
    }

    private func batchFlipFlagged(ids: [String], to flagged: Bool) async {
        let idsSet = Set(ids)
        flipFlagged(matching: idsSet, to: flagged)
        do {
            let failed = try await graphClient.batchSetFlagged(ids: ids, flagged: flagged)
            if !failed.isEmpty {
                flipFlagged(matching: failed, to: !flagged)
                logger.error("batchFlipFlagged(\(flagged)): \(failed.count) of \(ids.count) failed")
            }
        } catch {
            logger.error("batchFlipFlagged(\(flagged)) failed: \(error.localizedDescription, privacy: .public)")
            flipFlagged(matching: idsSet, to: !flagged)
        }
    }

    private func flipFlagged(matching ids: Set<String>, to flagged: Bool) {
        guard var current = summary?.emails else { return }
        for i in current.indices where ids.contains(current[i].id) {
            current[i] = current[i].with(isFlagged: flagged)
        }
        summary?.emails = current
    }

/// Optimistic: drops the row immediately, restores it (in received-time
    /// order) if the Graph PATCH fails.
    func markRead(emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let removed = summary?.emails.remove(at: idx) else { return }
        summary?.totalUnreadEmails -= 1
        defer { Task { await updateAppBadge() } }
        do {
            try await graphClient.markEmailRead(id: emailId)
        } catch {
            logger.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            let insertAt = summary?.emails.firstIndex(where: { $0.received < removed.received })
                ?? summary?.emails.count ?? 0
            summary?.emails.insert(removed, at: insertAt)
            summary?.totalUnreadEmails += 1
        }
    }

    /// Undo for the auto-mark-as-read that fires when the preview sheet
    /// opens. Re-inserts the email into the summary in received-time
    /// order so the user sees it back in CheckIn without having to
    /// pull-to-refresh. Failure is logged but silent.
    func markUnread(_ email: Email) async {
        do {
            try await graphClient.markEmailUnread(id: email.id)
            if summary?.emails.contains(where: { $0.id == email.id }) == false {
                let insertAt = summary?.emails.firstIndex(where: { $0.received < email.received })
                    ?? summary?.emails.count ?? 0
                summary?.emails.insert(email, at: insertAt)
            }
            summary?.totalUnreadEmails += 1
            await updateAppBadge()
        } catch {
            logger.error("markUnread failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Used by the preview sheet to render the full email body.
    /// Returns plain text — Graph delivers it that way because of the
    /// `Prefer: outlook.body-content-type="text"` header in the client.
    func fetchEmailBody(emailId: String) async throws -> String {
        try await graphClient.fetchEmailBody(id: emailId)
    }

    /// Send a reply-all to an email. After success the email is
    /// optimistically dropped from the visible summary (replying
    /// implies you've handled it) — same shape as markRead's path.
    func replyAllToEmail(emailId: String, comment: String) async throws {
        #if DEBUG
        logger.info("replyAllToEmail begin id=\(emailId, privacy: .public)")
        #endif
        try await graphClient.replyAllToEmail(id: emailId, comment: comment)
        #if DEBUG
        logger.info("replyAllToEmail graph ok id=\(emailId, privacy: .public)")
        #endif
        if let idx = summary?.emails.firstIndex(where: { $0.id == emailId }) {
            #if DEBUG
            logger.info("replyAllToEmail removing row at idx=\(idx, privacy: .public)")
            #endif
            summary?.emails.remove(at: idx)
            summary?.totalUnreadEmails = max(0, (summary?.totalUnreadEmails ?? 1) - 1)
            await updateAppBadge()
        } else {
            #if DEBUG
            logger.info("replyAllToEmail row already absent (auto-mark-read on preview)")
            #endif
        }
        // Mark the original as read on the server too — replying counts
        // as having handled the message. Fire-and-forget; if it fails
        // the next refresh will reconcile.
        Task { try? await graphClient.markEmailRead(id: emailId) }
        #if DEBUG
        logger.info("replyAllToEmail done id=\(emailId, privacy: .public)")
        #endif
    }

    /// Send a reply into an existing Teams chat thread. After success
    /// the chat is dropped from the summary's pending list — same shape
    /// as the email path.
    func sendChatMessage(chatId: String, content: String) async throws {
        try await graphClient.sendChatMessage(chatId: chatId, content: content)
        if let idx = summary?.chats.firstIndex(where: { $0.chatId == chatId }) {
            summary?.chats.remove(at: idx)
            await updateAppBadge()
        }
    }

    /// Mark a Teams chat as read for the signed-in user. Optimistically
    /// drops the chat from the summary. Requires the chat to have a
    /// `chatId` (set by `pendingChats`); otherwise no-op. Mirrors the
    /// email `markRead` shape — no undo banner (the Mark Unread button
    /// on the preview sheet covers the recovery path).
    func markChatRead(_ chat: ChatMessage) async {
        guard let chatId = chat.chatId else { return }
        let userId = graphClient.currentUserID
        guard let tenantId = authService.homeTenantId, !tenantId.isEmpty, !userId.isEmpty else {
            logger.error("markChatRead: missing userId or tenantId")
            return
        }
        let removedIdx = summary?.chats.firstIndex(where: { $0.chatId == chatId })
        if let idx = removedIdx {
            summary?.chats.remove(at: idx)
            await updateAppBadge()
        }
        do {
            try await graphClient.markChatRead(chatId: chatId, userId: userId, tenantId: tenantId)
        } catch {
            logger.error("markChatRead failed: \(error.localizedDescription, privacy: .public)")
            // Restore the row on failure.
            if removedIdx != nil, summary?.chats.contains(where: { $0.chatId == chatId }) == false {
                let insertAt = summary?.chats.firstIndex(where: { $0.sent < chat.sent })
                    ?? summary?.chats.count ?? 0
                summary?.chats.insert(chat, at: insertAt)
                await updateAppBadge()
            }
        }
    }

    /// Flip every read chat with a message from today back to unread,
    /// so a day's chat activity that got cleared elsewhere (Teams
    /// desktop, another mobile client) shows up in CheckIn again.
    /// Refreshes the summary and registers an undo. No Graph batch
    /// endpoint for chats, so this is a client-side loop.
    func markTodayChatsUnread() async {
        let userId = graphClient.currentUserID
        guard let tenantId = authService.homeTenantId, !tenantId.isEmpty, !userId.isEmpty else {
            logger.error("markTodayChatsUnread: missing userId or tenantId")
            return
        }
        do {
            let ids = try await graphClient.idsOfReadChatsToday()
            guard !ids.isEmpty else { return }
            for id in ids {
                try? await graphClient.markChatUnread(chatId: id, userId: userId, tenantId: tenantId)
            }
            await refreshChats()
            await updateAppBadge()
            setPendingUndo(UndoableBulkAction(
                summary: "Marked \(ids.count) chat\(ids.count == 1 ? "" : "s") unread",
                undo: { [weak self] in
                    guard let self else { return }
                    for id in ids {
                        try? await self.graphClient.markChatRead(chatId: id, userId: userId, tenantId: tenantId)
                    }
                    await self.refreshChats()
                    await self.updateAppBadge()
                }
            ))
        } catch {
            logger.error("markTodayChatsUnread failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-fetch the pending-chats list and slot it back into the
    /// summary. Used after bulk read-state mutations so the visible
    /// list reflects the new server-side viewpoint.
    private func refreshChats() async {
        guard teamsEnabled else { return }
        do {
            let chats = try await graphClient.pendingChats()
            summary?.chats = chats
        } catch {
            logger.error("refreshChats failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Mark a Teams chat as unread for the signed-in user. Re-inserts
    /// the chat into the visible list in sent-time order so the user
    /// sees the action immediately. Same shape as the email
    /// `markUnread` recovery path.
    func markChatUnread(_ chat: ChatMessage) async {
        guard let chatId = chat.chatId else { return }
        let userId = graphClient.currentUserID
        guard let tenantId = authService.homeTenantId, !tenantId.isEmpty, !userId.isEmpty else {
            logger.error("markChatUnread: missing userId or tenantId")
            return
        }
        do {
            try await graphClient.markChatUnread(chatId: chatId, userId: userId, tenantId: tenantId)
            if summary?.chats.contains(where: { $0.chatId == chatId }) == false {
                let insertAt = summary?.chats.firstIndex(where: { $0.sent < chat.sent })
                    ?? summary?.chats.count ?? 0
                summary?.chats.insert(chat, at: insertAt)
                await updateAppBadge()
            }
        } catch {
            logger.error("markChatUnread failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Optimistic. Mutates the matching meeting's `responseStatus`
    /// immediately so the UI updates, and reverts on failure. After a
    /// successful RSVP, also marks any invite emails still sitting unread
    /// in the inbox as read, and recomputes `hasConflict` on every meeting
    /// so a Decline removes the warning from the meetings that were
    /// previously conflicting with it. Operates on either `summary.meeting`
    /// or the matching entry in `summary.laterToday`.
    func respondToMeeting(_ response: MeetingResponse, meetingId: String? = nil) async {
        let id = meetingId ?? nextMeeting?.id
        guard let id, let meeting = meetingWithId(id) else { return }
        let previous = meeting.responseStatus
        setMeeting(meeting.with(responseStatus: response))
        recomputeConflicts()
        do {
            try await graphClient.respondToMeeting(id: meeting.id, response: response)
            await markMatchingInviteEmailsRead(for: meeting)
        } catch {
            logger.error("respondToMeeting(\(response.rawValue)) failed: \(error.localizedDescription, privacy: .public)")
            setMeeting(meeting.with(responseStatus: previous))
            recomputeConflicts()
        }
    }

    /// Optimistically remove the meeting from the summary, then DELETE
    /// via Graph. If it was the "next" meeting, the first `laterToday`
    /// meeting (if any) is promoted into its place. Recomputes
    /// `hasConflict` on the remaining meetings — a deletion may resolve
    /// conflicts elsewhere.
    func deleteMeeting(meetingId: String) async {
        guard let meeting = meetingWithId(meetingId) else { return }
        let meetingsByIdSnapshot = meetingsById
        let todayMeetingIdsSnapshot = todayMeetingIds
        let inviteEmailMeetingIdsSnapshot = inviteEmailMeetingIds
        let referenceMeetingIdsSnapshot = referenceMeetingIds

        // Pull the meeting out of every index and the master dict. If
        // it was today's next meeting, removing its id from the front
        // of `todayMeetingIds` automatically promotes whatever was
        // next in line — `nextMeeting` is computed from that list.
        todayMeetingIds.removeAll { $0 == meetingId }
        referenceMeetingIds.remove(meetingId)
        for (emailId, mId) in inviteEmailMeetingIds where mId == meetingId {
            inviteEmailMeetingIds.removeValue(forKey: emailId)
        }
        meetingsById.removeValue(forKey: meetingId)

        recomputeConflicts()

        do {
            try await graphClient.deleteEvent(id: meeting.id)
        } catch {
            logger.error("deleteEvent failed: \(error.localizedDescription, privacy: .public)")
            meetingsById = meetingsByIdSnapshot
            todayMeetingIds = todayMeetingIdsSnapshot
            inviteEmailMeetingIds = inviteEmailMeetingIdsSnapshot
            referenceMeetingIds = referenceMeetingIdsSnapshot
            recomputeConflicts()
        }
    }

    /// Recompute `hasConflict` on every meeting based on the current
    /// local state. Declined meetings are excluded from both sides of
    /// the overlap check — they don't trigger a warning on themselves
    /// (the user isn't going) and they don't count as conflicts for
    /// other meetings. Pool is the union of today's summary meetings,
    /// the Phase-2 invite cache, and the reference pool of plain
    /// calendar events covering the invite date range — so an invite
    /// can flag a conflict against a meeting the user already has on
    /// their schedule even when that meeting isn't an invitation.
    private func recomputeConflicts() {
        guard summary != nil else { return }
        let pool = Array(meetingsById.values)
        meetingsById = meetingsById.mapValues { $0.with(hasConflict: overlapsAny($0, in: pool)) }
    }

    private func overlapsAny(_ m: Meeting, in all: [Meeting]) -> Bool {
        if m.responseStatus == .declined { return false }
        return all.contains { other in
            other.id != m.id
                && other.responseStatus != .declined
                && other.start < m.end
                && m.start < other.end
        }
    }

    private func meetingWithId(_ id: String) -> Meeting? {
        meetingsById[id]
    }

    private func setMeeting(_ meeting: Meeting) {
        meetingsById[meeting.id] = meeting
    }

    /// Replace the today-window index and seed each Meeting into
    /// `meetingsById`. Called from `refresh()` after the calendar fetch
    /// returns. Old `summary.meeting` + `summary.laterToday` are still
    /// assigned alongside during the migration.
    private func loadTodayMeetings(next: Meeting?, laterToday: [Meeting]) {
        // Drop the previous today-window members from the master store
        // first, so a meeting that disappeared from the calendar
        // (declined/cancelled/deleted) doesn't linger.
        for id in todayMeetingIds {
            // Only drop ids that aren't ALSO referenced by another
            // index — a today meeting that's also an invite-email
            // referent should survive until its other index drops it.
            if !inviteEmailMeetingIds.values.contains(id) && !referenceMeetingIds.contains(id) {
                meetingsById.removeValue(forKey: id)
            }
        }
        var ids: [String] = []
        if let next {
            meetingsById[next.id] = next
            ids.append(next.id)
        }
        for m in laterToday {
            meetingsById[m.id] = m
            ids.append(m.id)
        }
        todayMeetingIds = ids
    }

    /// Find invitation/update/cancellation emails for this meeting and
    /// mark them read. Bounded to the local unread list, so it can't
    /// reach beyond what we already have cached.
    ///
    /// Matching strategy is two-tiered:
    /// 1. Standard subject match (using `normalizedSubjectKey` so
    ///    Re:/Fwd: prefixes and whitespace don't get in the way) plus the
    ///    "Updated:" and "Cancelled:" prefix variants Outlook uses.
    /// 2. For confirmed meeting messages (Graph's `meetingMessageType`
    ///    is set) coming from the meeting's organizer, a contains-match
    ///    handles tenant-specific prefixes like "Meeting request:" or
    ///    "Invitation:" — the two-factor (organizer + meeting-message)
    ///    keeps false positives down.
    /// Inverse of `markMatchingInviteEmailsRead`: given an invite email,
    /// find the meeting in our current summary that it refers to. Used
    /// to drive the inline RSVP buttons on invite-email rows so a
    /// chosen response from the email surface routes through the same
    /// `respondToMeeting(_:meetingId:)` path as the calendar card — and
    /// inherits all the downstream syncing (meeting card updates,
    /// matching invite emails marked read, conflicts recomputed).
    ///
    /// Falls back to the `inviteMeetings` cache (Phase 2) when no
    /// today-window meeting matches — that cache is populated by the
    /// `$expand=event` ride-along on `unreadEmails` and covers invites
    /// for meetings beyond today's calendar window.
    func meetingMatching(_ email: Email) -> Meeting? {
        var todays: [Meeting] = []
        if let m = nextMeeting { todays.append(m) }
        todays.append(contentsOf: laterToday)
        if let match = todays.first(where: { $0.matches(email) }) { return match }
        if let meetingId = inviteEmailMeetingIds[email.id] { return meetingsById[meetingId] }
        return nil
    }

    private func markMatchingInviteEmailsRead(for meeting: Meeting) async {
        let matchIds = (summary?.emails ?? [])
            .filter { meeting.matches($0) }
            .map(\.id)
        for id in matchIds {
            await markRead(emailId: id)
        }
    }

    /// Optimistic. Caller passes the desired state rather than asking us to
    /// flip what we read, so rapid double-swipes can't oscillate against
    /// stale state.
    func setFlagged(_ flagged: Bool, emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let original = summary?.emails[idx] else { return }
        summary?.emails[idx] = original.with(isFlagged: flagged)
        do {
            if flagged {
                try await graphClient.flagEmail(id: emailId)
            } else {
                try await graphClient.unflagEmail(id: emailId)
            }
        } catch {
            logger.error("setFlagged(\(flagged)) failed: \(error.localizedDescription, privacy: .public)")
            summary?.emails[idx] = original
        }
    }

    private func fetchMeetings() async -> (next: Meeting?, laterToday: [Meeting], failed: Bool) {
        do {
            let r = try await graphClient.todaysMeetings()
            return (r.next, r.laterToday, false)
        } catch {
            logger.error("todaysMeetings failed: \(error.localizedDescription, privacy: .public)")
            return (nil, [], true)
        }
    }

    /// Best-effort. Fetch calendar events overlapping the date range
    /// spanned by the supplied invite emails (their `meetingStart` /
    /// `meetingEnd` are read straight off Graph's eventMessage subtype).
    /// Doubles as both the conflict-detection reference pool and the
    /// source of truth for matching invite emails to their underlying
    /// event — `$expand=event` returns empty stubs for future
    /// invitations, so we sidestep it. Returns an empty pool on failure
    /// (no banner; UX enhancement only). Skipped when there are no
    /// invites with dates.
    private func fetchConflictReferenceMeetings(for inviteEmails: [Email]) async -> [Meeting] {
        let starts = inviteEmails.compactMap(\.meetingStart)
        let ends = inviteEmails.compactMap(\.meetingEnd)
        guard let earliest = starts.min(), let latest = ends.max() else { return [] }
        do {
            return try await graphClient.eventsInRange(start: earliest, end: latest)
        } catch {
            logger.error("fetchConflictReferenceMeetings failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Match `meetingRequest` invite emails to their underlying event in
    /// `calendar` so the email row can surface meeting time / RSVP /
    /// conflict. Match key is normalized subject + start time within a
    /// minute — subject alone is ambiguous when multiple meetings share a
    /// title, but `meetingStart` from the eventMessage and `start` from
    /// the calendar event come from the same source-of-truth and should
    /// be exact. Returns a map keyed by email id; emails with no
    /// matching event simply don't appear (the row falls back to
    /// regular-email rendering).
    /// Resolve each `meetingRequest` invite email to a calendar event
    /// so the row can surface meeting time / RSVP / conflict. Two-pass
    /// match:
    /// 1. Subject + start-time-within-a-minute against the calendar
    ///    pool. Free, no Graph call, covers the common case.
    /// 2. Fallback: pull `iCalUId` from the invitation's
    ///    `PidLidGlobalObjectId` MAPI property and look up the calendar
    ///    pool by that. Deterministic — disambiguates same-subject
    ///    collisions and rescheduled meetings whose start time on the
    ///    invitation no longer matches the calendar entry. The looked-up
    ///    Meeting carries the real event id and responseStatus; no
    ///    synthetic placeholders.
    ///
    /// Invites with no matching event in either pass are returned
    /// absent from the map. The row's "Removed" pill takes that case
    /// (event was declined, deleted, or cancelled — the absence is
    /// the signal).
    private func matchInvitesToCalendar(emails: [Email], calendar: [Meeting]) async -> [String: Meeting] {
        var result: [String: Meeting] = [:]
        for email in emails where email.isInvite {
            if let match = calendar.first(where: { $0.matches(email) }) {
                result[email.id] = match
                continue
            }
            guard let iCalUId = await graphClient.fetchInviteICalUId(messageId: email.id) else { continue }
            if let match = calendar.first(where: {
                $0.iCalUId?.caseInsensitiveCompare(iCalUId) == .orderedSame
            }) {
                result[email.id] = match
            }
        }
        return result
    }

    private func fetchEmails() async -> (emails: [Email], totalCount: Int, failed: Bool) {
        do {
            let r = try await graphClient.unreadEmails(top: emailTop)
            return (r.emails, r.totalCount, false)
        } catch {
            logger.error("unreadEmails failed: \(error.localizedDescription, privacy: .public)")
            return ([], 0, true)
        }
    }

    /// Apply a fresh `fetchEmails` result to `summary.emails` and rebuild
    /// the derived invite caches (`conflictReferenceMeetings` first, then
    /// `inviteMeetings` matched off it). Every code path that retouches
    /// `summary.emails` calls this so the invite-row UI and conflict pool
    /// stay coherent — otherwise mark-read/unread can leave stale invite
    /// state pointing at events that are no longer in the unread window.
    private func applyEmailsResult(_ result: (emails: [Email], totalCount: Int, failed: Bool)) async {
        summary?.emails = result.emails
        summary?.totalUnreadEmails = result.totalCount
        await rebuildInviteCaches(from: result.emails)
    }

    /// Rebuild `conflictReferenceMeetings` + `inviteMeetings` from the
    /// given email list and recompute conflict flags. Caller is
    /// responsible for assigning `summary.emails` first if needed.
    /// Used by both `refresh()` (after constructing a fresh summary)
    /// and `applyEmailsResult` (after a mid-session email refresh).
    private func rebuildInviteCaches(from emails: [Email]) async {
        let inviteEmails = emails.filter(\.isInvite)
        let referenceMeetings = await fetchConflictReferenceMeetings(for: inviteEmails)
        let matchedInvites = await matchInvitesToCalendar(emails: emails, calendar: referenceMeetings)

        // Drop any previous invite/reference members from the master
        // store that aren't in today's window and aren't in the new
        // sets — otherwise stale meetings linger.
        let keepTodayIds = Set(todayMeetingIds)
        for id in inviteEmailMeetingIds.values where !keepTodayIds.contains(id) {
            meetingsById.removeValue(forKey: id)
        }
        for id in referenceMeetingIds where !keepTodayIds.contains(id) {
            meetingsById.removeValue(forKey: id)
        }
        inviteEmailMeetingIds.removeAll(keepingCapacity: true)
        referenceMeetingIds.removeAll(keepingCapacity: true)
        for (emailId, m) in matchedInvites {
            meetingsById[m.id] = m
            inviteEmailMeetingIds[emailId] = m.id
        }
        for m in referenceMeetings {
            meetingsById[m.id] = m
            referenceMeetingIds.insert(m.id)
        }

        recomputeConflicts()
    }

    /// Captured by `setPendingUndo`; rendered by `SummaryView` as the
    /// floating undo banner with the summary string and an Undo button
    /// that calls `Inbox.performUndo`.
    struct UndoableBulkAction {
        let summary: String
        let undo: @MainActor () async -> Void
    }

    /// Best-effort presence read. Failures don't bump `lastRefreshFailed`
    /// — presence is a secondary concern, not critical to the panel.
    /// Returns the presence plus the custom status message so callers
    /// can publish both in lockstep from a single Graph round-trip.
    private func fetchPresence() async -> (Presence, String) {
        guard teamsEnabled else { return (.unknown, "") }
        do {
            return try await graphClient.fetchPresence()
        } catch {
            logger.error("fetchPresence failed: \(error.localizedDescription, privacy: .public)")
            return (.unknown, "")
        }
    }

    /// Returns an empty array when Teams is disabled or `fetchUserID` failed
    /// — the pending-chat heuristic compares against the signed-in user's
    /// ID, so without that the call can't be made meaningfully. The early
    /// returns aren't treated as failures.
    private func fetchChats(userIDReady: Bool) async -> (chats: [ChatMessage], failed: Bool) {
        guard teamsEnabled, userIDReady else { return ([], false) }
        do {
            return (try await graphClient.pendingChats(), false)
        } catch {
            logger.error("pendingChats failed: \(error.localizedDescription, privacy: .public)")
            return ([], true)
        }
    }
}
