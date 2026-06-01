// RelativeTime.swift
// CheckInKit
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

/// Format the gap from `referenceDate` to a future `date` as a human
/// phrase: "now", "soon", "in N min", "in N hour(s)", "in Nh Mm".
/// The widget passes the timeline entry's date so the countdown advances
/// across the per-minute entries `countdownTimelineDates` generates; the
/// in-app surface passes `.now` and re-renders periodically.
public func untilTime(_ date: Date, referenceDate: Date) -> String {
    let seconds = date.timeIntervalSince(referenceDate)

    if seconds < 0 {
        return "now"
    }
    if seconds <= 180 {
        return "soon"
    }

    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours == 0 {
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }
    if minutes == 0 {
        return hours == 1 ? "in 1 hour" : "in \(hours) hours"
    }
    return "in \(hours)h \(minutes)m"
}

/// Timeline entry dates for a countdown widget: one entry per minute from
/// `now` out to `horizonMinutes`, plus each meeting start so the display
/// flips to the right meeting at the exact transition rather than waiting
/// for the next minute tick. Sorted ascending and de-duplicated. Shared by
/// the iPhone and watch timeline providers so their "in N min" countdowns
/// advance identically and can't drift apart (the watch provider once
/// emitted only the meeting-start entries, which froze the countdown
/// between reloads).
public func countdownTimelineDates(from now: Date, horizonMinutes: Int, meetingStarts: [Date]) -> [Date] {
    var dates = Set<Date>()
    for minute in 0...horizonMinutes {
        dates.insert(now.addingTimeInterval(TimeInterval(minute * 60)))
    }
    for start in meetingStarts {
        dates.insert(start)
    }
    return dates.sorted()
}

/// True when the meeting starts within the next three minutes of
/// `referenceDate` (and hasn't started yet). Drives the orange
/// "soon" treatment on the meeting card and widget pill.
public func isMeetingImminent(_ date: Date, referenceDate: Date) -> Bool {
    let seconds = date.timeIntervalSince(referenceDate)
    return seconds >= 0 && seconds <= 180
}

/// True once a meeting has started (its start is at or before
/// `referenceDate`). The watch surfaces tint the calendar icon on this.
public func meetingInProgress(start: Date, referenceDate: Date) -> Bool {
    start <= referenceDate
}

/// True when a meeting should get the "soon/now" orange highlight: already
/// in progress, or imminent (starting within three minutes). The single
/// source for the live-highlight rule the meeting card, widgets, and watch
/// rows all share — it drives the orange countdown everywhere and the
/// orange calendar icon on the phone surfaces.
public func meetingIsLive(start: Date, referenceDate: Date) -> Bool {
    meetingInProgress(start: start, referenceDate: referenceDate)
        || isMeetingImminent(start, referenceDate: referenceDate)
}

/// Compact meeting time range in 12-hour US format, e.g. "9-9:30 PM"
/// when both ends fall in the same period, or "11:30 AM-12:30 PM" when
/// the meeting crosses noon (or midnight). Drops `:00` for on-the-hour
/// times so "9-10 PM" reads cleaner than "9:00-10:00 PM". Pass
/// `includePeriod: false` to drop the AM/PM marker entirely — used on
/// the watch glance's "Later today" rows where width is tight and the
/// user's mental model of "today" already pins the period.
public func meetingTimeRange(start: Date, end: Date, includePeriod: Bool = true) -> String {
    let cal = Calendar.current
    let startHour = cal.component(.hour, from: start)
    let startMinute = cal.component(.minute, from: start)
    let endHour = cal.component(.hour, from: end)
    let endMinute = cal.component(.minute, from: end)
    let startPM = startHour >= 12
    let endPM = endHour >= 12
    let startHour12 = (startHour % 12 == 0) ? 12 : startHour % 12
    let endHour12 = (endHour % 12 == 0) ? 12 : endHour % 12
    let startStr = startMinute == 0
        ? "\(startHour12)"
        : "\(startHour12):" + String(format: "%02d", startMinute)
    let endStr = endMinute == 0
        ? "\(endHour12)"
        : "\(endHour12):" + String(format: "%02d", endMinute)
    guard includePeriod else {
        return "\(startStr)-\(endStr)"
    }
    if startPM == endPM {
        let period = endPM ? "PM" : "AM"
        return "\(startStr)-\(endStr) \(period)"
    }
    return "\(startStr) \(startPM ? "PM" : "AM")-\(endStr) \(endPM ? "PM" : "AM")"
}
