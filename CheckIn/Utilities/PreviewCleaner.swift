// PreviewCleaner.swift
// CheckIn
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

// Salutation: matches the openers (Hi/Hello/Hey/Dear/Greetings/Good
// morning|afternoon|evening|day), allows up to ~60 chars of name/team,
// requires a comma or exclamation, and crucially requires a newline at
// the end — so a same-line "Hi David, please review" stays intact and
// only a salutation on its own line gets stripped.
private let salutationRegex = try? NSRegularExpression(
    pattern: #"^(hi|hello|hey|dear|greetings|good\s+(morning|afternoon|evening|day))\b[^\n,!]{0,60}[,!]\s*\n"#,
    options: .caseInsensitive
)

// "On <date>, <name> <email> wrote:" reply marker. Conservative
// 200-char bound so a wandering "wrote:" elsewhere doesn't grab the
// whole preview.
private let onWroteRegex = try? NSRegularExpression(
    pattern: #"\n+On\s+[^\n]{0,200}wrote:"#,
    options: .caseInsensitive
)

// Outlook's quoted-reply header always starts with "From:" on its own
// line. Cutting here also handles "From: ... Sent: ... To: ..." chains.
private let fromHeaderRegex = try? NSRegularExpression(
    pattern: #"\n+From:\s+"#,
    options: .caseInsensitive
)

// Common signature markers — RFC 3676 separator "-- ", mobile sigs
// like "Sent from my iPhone", Microsoft's auto-promo footers, etc.
// Cuts at the first match so anything after is treated as signature.
private let signatureMarkerRegex = try? NSRegularExpression(
    pattern: #"\n+(--\s*\n|Sent from my [^\n]{0,30}|Sent from Outlook[^\n]*|Get Outlook for[^\n]*|Sent via [^\n]*)"#,
    options: .caseInsensitive
)

// Valediction line on its own — "Thanks,\n", "Best regards,\n", etc.
// Require a comma (not !) because casual mid-paragraph "Thanks!" isn't
// a valediction. The mandatory trailing newline keeps single-line
// "Thanks, John, can you review?" intact.
private let valedictionRegex = try? NSRegularExpression(
    pattern: #"\n+(Thanks|Thank you|Regards|Best|Best regards|Kind regards|Cheers|Sincerely|Best wishes|Take care|Warm regards|All the best)\s*,\s*\n"#,
    options: .caseInsensitive
)

// Horizontal-rule-style separator lines — Outlook uses long runs of
// underscores between the reply body and quoted content, and meeting
// invites use them to fence off the Teams join section. 4+ consecutive
// is the threshold (3 dashes could be legitimate text). `(^|\n+)` so
// a separator at the very start of the preview also triggers — the
// meeting-invite case has the underscores leading.
private let separatorLineRegex = try? NSRegularExpression(
    pattern: #"(^|\n+)[_\-=]{4,}"#
)

// Collapse runs of blank lines down to a single newline. Treats lines
// that are only spaces or tabs as blank — HTML emails commonly produce
// `"Line 1\n \nLine 2"` after stripping `&nbsp;` between `<br>` tags,
// and a pure `\n{2,}` pattern misses that.
private let collapseBlankLinesRegex = try? NSRegularExpression(pattern: #"\n([ \t]*\n)+"#)

// Image placeholders left by Exchange's HTML→text body conversion. Each
// `<img>` becomes its alt text in square brackets — "[Calendar Icon]",
// "[Sharing Laptop Image]" — or a "[cid:…]" / "[logo.png]" reference. We
// only strip brackets that carry an image marker (a cid, an image file
// extension, or an image-ish word), so genuine bracketed text like
// "[EXTERNAL]" or "[Action Required]" survives.
private let imagePlaceholderRegex = try? NSRegularExpression(
    pattern: #"\[[^\]\n]*(?:cid:|\.(?:png|jpe?g|gif|svg|bmp|webp|tiff?|ico)\b|\b(?:image|images|icon|logo|photo|picture|graphic|graphics|banner|avatar|thumbnail|headshot|spacer|pixel)\b)[^\]\n]*\]"#,
    options: .caseInsensitive
)

// Empty brackets, the residue of an image with no alt text.
private let emptyBracketRegex = try? NSRegularExpression(pattern: #"\[[ \t]*\]"#)

// Collapse runs of spaces/tabs (but not newlines) to one space, so removing
// an inline placeholder doesn't leave "word  word" double-spaced.
private let horizontalSpaceRegex = try? NSRegularExpression(pattern: #"[^\S\n]{2,}"#)

/// Clean Graph's `bodyPreview` down to the meat of the latest message.
/// - Strips a leading salutation only when it occupies its own line.
/// - Cuts at the first quoted-reply marker (`"On … wrote:"` or
///   Outlook's `"From: …"` header) and discards everything after.
/// - Runs the result through `stripHTML` for safety in case Graph
///   ever returns HTML in `bodyPreview` for some accounts.
/// - Drops image placeholders ("[Calendar Icon]", "[cid:…]") that
///   Exchange's HTML→text conversion leaves in the body.
/// - Collapses blank lines and trims surrounding whitespace.
func cleanEmailPreview(_ raw: String) -> String {
    // Graph returns CRLF (`\r\n`) for line endings. Normalize to LF so
    // every regex below — which only knows about `\n` — works as
    // intended. A stray `\r` (rare; some legacy mail clients) gets
    // mapped to `\n` too.
    var s = raw.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    s = stripHTML(s)

    // Drop image placeholders (e.g. "[Calendar Icon]") that Exchange's text
    // conversion leaves behind, then close the horizontal gap an inline one
    // leaves. Own-line placeholders become blank lines that the blank-line
    // collapse below removes.
    if let regex = imagePlaceholderRegex {
        s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let regex = emptyBracketRegex {
        s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let regex = horizontalSpaceRegex {
        s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ")
    }

    // Take the earliest of any quoted-reply or signature marker as the
    // cut point. Everything from there onward is discarded — that's
    // either someone else's prior message or a trailing signature, not
    // content the user wants to read in a 4-line preview.
    var cuts: [Int] = []
    let range = NSRange(s.startIndex..., in: s)
    if let m = onWroteRegex?.firstMatch(in: s, range: range) {
        cuts.append(m.range.location)
    }
    if let m = fromHeaderRegex?.firstMatch(in: s, range: range) {
        cuts.append(m.range.location)
    }
    if let m = signatureMarkerRegex?.firstMatch(in: s, range: range) {
        cuts.append(m.range.location)
    }
    if let m = valedictionRegex?.firstMatch(in: s, range: range) {
        cuts.append(m.range.location)
    }
    if let m = separatorLineRegex?.firstMatch(in: s, range: range) {
        cuts.append(m.range.location)
    }
    // Position-zero cuts are valid (e.g., a preview that begins with a
    // separator) — they result in an empty preview, which is the right
    // call for auto-generated content like meeting-invite metadata.
    if let cut = cuts.min() {
        s = String(s.prefix(cut))
    }

    // Strip a leading salutation line if present.
    if let regex = salutationRegex {
        let r = NSRange(s.startIndex..., in: s)
        if let m = regex.firstMatch(in: s, range: r), m.range.location == 0 {
            let endIdx = s.index(s.startIndex, offsetBy: m.range.length)
            s = String(s[endIdx...])
        }
    }

    // Collapse blank lines so empty space doesn't take up display lines.
    if let regex = collapseBlankLinesRegex {
        s = regex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n"
        )
    }

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
