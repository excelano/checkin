// Inbox.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import UserNotifications
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

    private let graphClient: GraphClient
    private let teamsEnabled: Bool
    private var didFetchUserID = false
    private var lastRefreshedAt: Date?
    private var didRequestBadgeAuthorization = false

    private var emailTop: Int { showingAllEmails ? 999 : 20 }

    @ObservationIgnored private let logger = Logger(subsystem: "com.excelano.checkin", category: "inbox")

    init(graphClient: GraphClient, teamsEnabled: Bool) {
        self.graphClient = graphClient
        self.teamsEnabled = teamsEnabled
        self.showingAllEmails = UserDefaults.standard.bool(forKey: AppStorageKey.showingAllEmails)
    }

    /// Toggle the email cap and refetch just the emails. No need to ripple
    /// meeting/chat updates.
    func setShowingAllEmails(_ show: Bool) async {
        guard show != showingAllEmails else { return }
        showingAllEmails = show
        UserDefaults.standard.set(show, forKey: AppStorageKey.showingAllEmails)
        let result = await fetchEmails()
        summary?.emails = result.emails
        summary?.totalUnreadEmails = result.totalCount
        if result.failed { lastRefreshFailed = true }
    }

    func refresh() async {
        var anyFailed = false
        var userIDReady = !teamsEnabled || didFetchUserID
        if teamsEnabled && !didFetchUserID {
            do {
                try await graphClient.fetchUserID()
                didFetchUserID = true
                userIDReady = true
            } catch {
                logger.error("fetchUserID failed: \(error.localizedDescription, privacy: .public)")
                userIDReady = false
                anyFailed = true
            }
        }

        async let meetingsT = fetchMeetings()
        async let emailsT = fetchEmails()
        async let chatsT = fetchChats(userIDReady: userIDReady)
        let meetingsResult = await meetingsT
        let emailsResult = await emailsT
        let (chats, chatsFailed) = await chatsT
        summary = CheckInSummary(meeting: meetingsResult.next,
                                 laterToday: meetingsResult.laterToday,
                                 emails: emailsResult.emails,
                                 chats: chats,
                                 totalUnreadEmails: emailsResult.totalCount)
        lastRefreshedAt = Date()
        lastRefreshFailed = anyFailed || meetingsResult.failed || emailsResult.failed || chatsFailed
        await updateAppBadge()
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
        await performMarkRead(emails: summary?.emails ?? [])
    }

    /// Mark the visible emails classified as "Other" by Microsoft's Focused
    /// Inbox ML. Leaves "Focused" emails alone.
    func markOtherInboxRead() async {
        let candidates = (summary?.emails ?? []).filter { $0.inferenceClassification == "other" }
        await performMarkRead(emails: candidates)
    }

    /// Mark meeting cancellations and RSVP responses (the noise that piles
    /// up after the actionable invite). The original `meetingRequest`
    /// invite is left alone — the user might still need to RSVP to it.
    func markMeetingNoticesRead() async {
        let noise: Set<String> = [
            "meetingCancelled",
            "meetingAccepted",
            "meetingTentativelyAccepted",
            "meetingDeclined"
        ]
        let candidates = (summary?.emails ?? []).filter {
            guard let t = $0.meetingMessageType else { return false }
            return noise.contains(t)
        }
        await performMarkRead(emails: candidates)
    }

    /// Mark visible emails that look like mailing-list traffic
    /// (RFC 2369 `List-Unsubscribe` header present).
    func markMailingListsRead() async {
        let candidates = (summary?.emails ?? []).filter { $0.isMailingList }
        await performMarkRead(emails: candidates)
    }

    /// Mark every visible email from the given SMTP address as read.
    /// Used by the row-level context menu.
    func markAllFromSenderRead(_ address: String) async {
        guard !address.isEmpty else { return }
        let candidates = (summary?.emails ?? []).filter { $0.fromAddress == address }
        await performMarkRead(emails: candidates)
    }

    /// Mark every visible email whose normalized subject matches. Strips
    /// Re:/Fwd: prefixes and ignores case, so a thread of replies all
    /// group together. Useful for dismissing a noisy thread or
    /// notification series in one move.
    func markAllWithSubjectRead(_ subject: String) async {
        let key = subject.normalizedSubjectKey
        guard !key.isEmpty else { return }
        let candidates = (summary?.emails ?? []).filter { $0.subject.normalizedSubjectKey == key }
        await performMarkRead(emails: candidates)
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
                summary?.emails = result.emails
                summary?.totalUnreadEmails = result.totalCount
                if result.failed { lastRefreshFailed = true }
            }
            await updateAppBadge()
        } catch {
            logger.error("performMarkRead failed: \(error.localizedDescription, privacy: .public)")
            summary?.emails.append(contentsOf: preserved)
            summary?.emails.sort { $0.received > $1.received }
            summary?.totalUnreadEmails += ids.count
        }
    }

    /// Optimistically flips the flag on every visible email not already in
    /// the target state, sends a single Graph `$batch` PATCH, and reverts
    /// only the emails that came back non-2xx.
    func setFlaggedAllVisible(_ flagged: Bool) async {
        let targets = (summary?.emails ?? []).filter { $0.isFlagged != flagged }
        let ids = Set(targets.map(\.id))
        guard !ids.isEmpty else { return }

        flipFlagged(matching: ids, to: flagged)

        do {
            let failed = try await graphClient.batchSetFlagged(ids: Array(ids), flagged: flagged)
            if !failed.isEmpty {
                flipFlagged(matching: failed, to: !flagged)
                logger.error("setFlaggedAllVisible(\(flagged)): \(failed.count) of \(ids.count) failed")
            }
        } catch {
            logger.error("setFlaggedAllVisible(\(flagged)) failed: \(error.localizedDescription, privacy: .public)")
            flipFlagged(matching: ids, to: !flagged)
        }
    }

    private func flipFlagged(matching ids: Set<String>, to flagged: Bool) {
        guard var current = summary?.emails else { return }
        for i in current.indices where ids.contains(current[i].id) {
            current[i] = current[i].with(isFlagged: flagged)
        }
        summary?.emails = current
    }

    /// Optimistic delete. Drops the row immediately, restores it if the
    /// Graph DELETE fails. Graph moves the message to Deleted Items rather
    /// than purging it, so the user can recover via Outlook.
    func deleteEmail(emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let removed = summary?.emails.remove(at: idx) else { return }
        summary?.totalUnreadEmails -= 1
        do {
            try await graphClient.deleteEmail(id: emailId)
            await updateAppBadge()
        } catch {
            logger.error("deleteEmail failed: \(error.localizedDescription, privacy: .public)")
            let insertAt = summary?.emails.firstIndex(where: { $0.received < removed.received })
                ?? summary?.emails.count ?? 0
            summary?.emails.insert(removed, at: insertAt)
            summary?.totalUnreadEmails += 1
        }
    }

    /// Optimistic: drops the row immediately, restores it (in received-time
    /// order) if the Graph PATCH fails.
    func markRead(emailId: String) async {
        guard let idx = summary?.emails.firstIndex(where: { $0.id == emailId }),
              let removed = summary?.emails.remove(at: idx) else { return }
        summary?.totalUnreadEmails -= 1
        do {
            try await graphClient.markEmailRead(id: emailId)
            await updateAppBadge()
        } catch {
            logger.error("markRead failed: \(error.localizedDescription, privacy: .public)")
            let insertAt = summary?.emails.firstIndex(where: { $0.received < removed.received })
                ?? summary?.emails.count ?? 0
            summary?.emails.insert(removed, at: insertAt)
            summary?.totalUnreadEmails += 1
        }
    }

    /// Optimistic. Mutates the matching meeting's `responseStatus`
    /// immediately so the UI updates, and reverts on failure. After a
    /// successful RSVP, also marks any invite emails still sitting unread
    /// in the inbox as read. Operates on either `summary.meeting` or the
    /// matching entry in `summary.laterToday`.
    func respondToMeeting(_ response: MeetingResponse, meetingId: String? = nil) async {
        let id = meetingId ?? summary?.meeting?.id
        guard let id, let meeting = meetingWithId(id) else { return }
        let previous = meeting.responseStatus
        setMeeting(meeting.with(responseStatus: response))
        do {
            try await graphClient.respondToMeeting(id: meeting.id, response: response)
            await markMatchingInviteEmailsRead(for: meeting)
        } catch {
            logger.error("respondToMeeting(\(response.rawValue)) failed: \(error.localizedDescription, privacy: .public)")
            setMeeting(meeting.with(responseStatus: previous))
        }
    }

    private func meetingWithId(_ id: String) -> Meeting? {
        if let m = summary?.meeting, m.id == id { return m }
        return summary?.laterToday.first(where: { $0.id == id })
    }

    private func setMeeting(_ meeting: Meeting) {
        if summary?.meeting?.id == meeting.id {
            summary?.meeting = meeting
            return
        }
        if let idx = summary?.laterToday.firstIndex(where: { $0.id == meeting.id }) {
            summary?.laterToday[idx] = meeting
        }
    }

    /// Subject-matches against the three invite-side forms Outlook uses
    /// ("Sprint Planning", "Updated: Sprint Planning", "Cancelled: Sprint
    /// Planning"). Bounded to the local unread list, so it can't reach
    /// beyond the 20 newest emails we already have.
    private func markMatchingInviteEmailsRead(for meeting: Meeting) async {
        let target = meeting.subject.lowercased()
        let acceptable: Set<String> = [target, "updated: \(target)", "cancelled: \(target)"]
        let matchIds = (summary?.emails ?? [])
            .filter { acceptable.contains($0.subject.lowercased()) }
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

    private func fetchEmails() async -> (emails: [Email], totalCount: Int, failed: Bool) {
        do {
            let r = try await graphClient.unreadEmails(top: emailTop)
            return (r.emails, r.totalCount, false)
        } catch {
            logger.error("unreadEmails failed: \(error.localizedDescription, privacy: .public)")
            return ([], 0, true)
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
