// BulkActionsMenu.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct BulkActionsMenu: View {
    let emails: [Email]
    let totalUnread: Int
    let isShowingAll: Bool
    let userMailDomain: String
    let onMarkAllRead: () -> Void
    let onMarkOtherRead: () -> Void
    let onMarkMeetingNoticesRead: () -> Void
    let onMarkMailingListsRead: () -> Void
    let onMarkExternalRead: () -> Void
    let onFlagAll: () -> Void
    let onUnflagAll: () -> Void
    let onShowAll: () -> Void
    let onShowCapped: () -> Void
    let onMarkTodayUnread: () -> Void

    var body: some View {
        let unflaggedCount = emails.filter { !$0.isFlagged }.count
        let flaggedCount = emails.count - unflaggedCount
        let otherCount = emails.filter { $0.inferenceClassification == "other" }.count
        let meetingNoticeCount = emails.filter(\.isMeetingNotice).count
        let mailingListCount = emails.filter { $0.isMailingList }.count
        let externalCount = externalSenderCount(in: emails, userMailDomain: userMailDomain)
        let canExpand = !isShowingAll && totalUnread > emails.count
        let hasItemsAbove = !emails.isEmpty || canExpand || isShowingAll

        Menu {
            if !emails.isEmpty {
                Button(action: onMarkAllRead) {
                    Label("Mark \(emails.count) read", systemImage: "envelope.open")
                }
            }
            if otherCount > 0 {
                Button(action: onMarkOtherRead) {
                    Label("Mark \(otherCount) in Other read", systemImage: "tray.2")
                }
            }
            if meetingNoticeCount > 0 {
                Button(action: onMarkMeetingNoticesRead) {
                    Label("Mark \(meetingNoticeCount) meeting notices read", systemImage: "calendar.badge.checkmark")
                }
            }
            if mailingListCount > 0 {
                Button(action: onMarkMailingListsRead) {
                    Label("Mark \(mailingListCount) mailing lists read", systemImage: "newspaper")
                }
            }
            if externalCount > 0 {
                Button(action: onMarkExternalRead) {
                    Label("Mark \(externalCount) external senders read", systemImage: "globe")
                }
            }
            if unflaggedCount > 0 {
                Button(action: onFlagAll) {
                    Label("Flag \(unflaggedCount)", systemImage: "flag")
                }
            }
            if flaggedCount > 0 {
                Button(action: onUnflagAll) {
                    Label("Unflag \(flaggedCount)", systemImage: "flag.slash")
                }
            }
            if canExpand {
                Divider()
                Button(action: onShowAll) {
                    Label("Show all \(totalUnread)", systemImage: "list.bullet")
                }
            } else if isShowingAll {
                Divider()
                Button(action: onShowCapped) {
                    Label("Show top 20", systemImage: "list.bullet")
                }
            }
            if hasItemsAbove { Divider() }
            Button(action: onMarkTodayUnread) {
                Label("Mark today's emails unread", systemImage: "envelope.badge")
            }
        } label: {
            ZStack {
                // Invisible text reserves the same vertical space as the
                // count pill, so the two capsules render the same height
                // despite an SF Symbol having no ascender/descender.
                Text("0").opacity(0)
                Image(systemName: "ellipsis")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .background(Brand.bgDarker)
            .clipShape(Capsule())
        }
        .accessibilityLabel("Bulk email actions")
    }

    private func externalSenderCount(in emails: [Email], userMailDomain: String) -> Int {
        guard !userMailDomain.isEmpty else { return 0 }
        return emails.filter { e in
            guard !e.fromAddress.isEmpty,
                  let atIdx = e.fromAddress.firstIndex(of: "@") else { return false }
            return e.fromAddress[e.fromAddress.index(after: atIdx)...].lowercased() != userMailDomain
        }.count
    }
}
