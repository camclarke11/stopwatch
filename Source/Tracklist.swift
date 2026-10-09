import Foundation

struct Track: Codable, Equatable {
    var seconds: Int
    var title: String
    // What the comment says about the track, such as a footnote marker's meaning from its legend.
    var note: String? = nil
}

// A pasted YouTube song or mix, kept between launches.
struct MusicLink: Codable, Equatable {
    var id: String
    var title: String
    var author: String
    var thumbnail: String
    var tracks: [Track]
}

enum Tracklist {
    static let minimumTracks = 3
    // Enough tracks to stop reading more comments.
    static let fullTracklist = 8
    static let titleLimit = 120

    static func videoID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isID: (String) -> Bool = { $0.count == 11 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") } }
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed), let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if host == "youtu.be" || host == "www.youtu.be" { return parts.first.flatMap { isID($0) ? $0 : nil } }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com") else { return nil }
        if parts.first == "watch" {
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            return value.flatMap { isID($0) ? $0 : nil }
        }
        if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]), isID(parts[1]) { return parts[1] }
        return nil
    }

    // The comment with the most usable timestamps wins; earlier (pinned, top) comments win ties.
    // The video description is only a fallback when no comment holds a tracklist.
    static func best(comments: [String], description: String?, duration: Int?) -> [Track] {
        var best: [Track] = []
        for comment in comments {
            let tracks = parse(comment, duration: duration)
            if tracks.count > best.count { best = tracks }
        }
        if best.count < minimumTracks, let description { best = parse(description, duration: duration) }
        return best.count >= minimumTracks ? best : []
    }

    // Timestamps with titles, in ascending order, inside the video and free of duplicates.
    static func parse(_ text: String, duration: Int?) -> [Track] {
        var found: [Track] = []
        let footnotes = legend(text)
        var previousHadTrack = false
        for rawLine in text.components(separatedBy: .newlines) {
            let line = String(rawLine.unicodeScalars.filter { !invisible.contains($0) })
            let ns = line as NSString
            let matches = timestamp.matches(in: line, range: NSRange(location: 0, length: ns.length))
            // An untimed "w/ …" line under a track says what was mixed with it.
            if matches.isEmpty {
                let extra = line.trimmingCharacters(in: .whitespaces)
                if previousHadTrack, mixedWith.firstMatch(in: extra, range: NSRange(location: 0, length: (extra as NSString).length)) != nil {
                    let note = [found[found.count - 1].note, extra].compactMap { $0 }.joined(separator: " · ")
                    found[found.count - 1].note = shorten(note, 2 * titleLimit)
                }
                previousHadTrack = false
                continue
            }
            let before = found.count
            defer { previousHadTrack = found.count > before }
            var index = 0
            while index < matches.count {
                let match = matches[index]
                let next = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                var title = clean(ns.substring(with: NSRange(location: NSMaxRange(match.range), length: next - NSMaxRange(match.range))))
                var used = 1
                // "0:00 - 3:45 Title" is a range: the second time ends the track.
                if title.isEmpty, index + 1 < matches.count {
                    let after = NSMaxRange(matches[index + 1].range)
                    let end = index + 2 < matches.count ? matches[index + 2].range.location : ns.length
                    title = clean(ns.substring(with: NSRange(location: after, length: end - after)))
                    used = 2
                }
                // "Title 3:45" puts the name first.
                if title.isEmpty, index == 0 { title = clean(ns.substring(to: match.range.location)) }
                // "(crowd on shoulders)" is a remark about the moment, not a song.
                if title.hasPrefix("("), title.hasSuffix(")"), balanced(String(title.dropFirst().dropLast())) { title = "" }
                if !title.isEmpty, let seconds = seconds(ns.substring(with: match.range)), duration.map({ seconds < $0 }) ?? true {
                    let (name, note) = annotate(title, footnotes)
                    if !name.isEmpty { found.append(Track(seconds: seconds, title: shorten(name, titleLimit), note: note.map { shorten($0, 2 * titleLimit) })) }
                }
                index += used
            }
        }
        return ascending(found)
    }

    static func seconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2 where parts[1] < 60: return parts[0] * 60 + parts[1]
        case 3 where parts[0] < 100 && parts[1] < 60 && parts[2] < 60: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"(?<![\d:.])\d{1,3}(?::\d{2}){1,2}(?![\d:])"#)
    private static let invisible: Set<Unicode.Scalar> = ["\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}"]
    private static let leading = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|:•·*>~=,.;)]}"))
    // Asterisks and other marks at the end of a title are footnote markers, so they stay.
    private static let trailing = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—|:•·=,;[({"))
    private static let numbering = try! NSRegularExpression(pattern: #"^(?:#?\d{1,3}[.)]|#\d{1,3})\s+"#)
    // Characters a comment lost in transit come through as runs of question marks.
    private static let unreadable = try! NSRegularExpression(pattern: #"\?{3,}$"#)
    private static let mixedWith = try! NSRegularExpression(pattern: #"^(?:w/|with\s|\+\s|&\s|vs\.?\s|x\s|->|→|into\s)"#, options: .caseInsensitive)
    // A legend line such as "* = unreleased", "** - released on SoundCloud" or "(U): unreleased".
    private static let legendLine = try! NSRegularExpression(pattern: #"^\s*([*†‡^+~°#]{1,3}|\([A-Za-z*†‡]{1,3}\)|\[[A-Za-z*†‡]{1,3}\])\s*(?:=|:|-|–|—|means)\s*(\S.*)$"#)

    static func legend(_ text: String) -> [(marker: String, meaning: String)] {
        var entries: [(marker: String, meaning: String)] = []
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            guard timestamp.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) == nil,
                  let match = legendLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let marker = ns.substring(with: match.range(at: 1))
            var meaning = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            // Keep the first sentence; the rest usually explains the note's format.
            if let stop = meaning.range(of: ". ") { meaning = String(meaning[..<stop.lowerBound]) }
            meaning = meaning.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            guard !meaning.isEmpty, !entries.contains(where: { $0.marker == marker }) else { continue }
            entries.append((marker, meaning.prefix(1).uppercased() + meaning.dropFirst()))
        }
        // Match "**" before "*".
        return entries.sorted { $0.marker.count > $1.marker.count }
    }

    // Splits "Song - Artist ** (alt, \"name\")" into the song and a note built from the legend.
    // Markers the comment never explains stay in the title as written.
    static func annotate(_ title: String, _ legend: [(marker: String, meaning: String)]) -> (String, String?) {
        let ns = title as NSString
        for entry in legend {
            let pattern = "(?:^|\\s)" + NSRegularExpression.escapedPattern(for: entry.marker) + "(?=\\s|$|\\()"
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: title, range: NSRange(location: 0, length: ns.length)) else { continue }
            let name = trim(ns.substring(to: match.range.location))
            var detail = ns.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
            if detail.hasPrefix("("), detail.hasSuffix(")"), balanced(String(detail.dropFirst().dropLast())) { detail = String(detail.dropFirst().dropLast()) }
            // "* Song" puts the marker first.
            if name.isEmpty { return detail.isEmpty ? (title, nil) : (trim(detail), entry.meaning) }
            return (name, [entry.meaning, detail].filter { !$0.isEmpty }.joined(separator: " · "))
        }
        return (title, nil)
    }

    private static func balanced(_ text: String) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 } else if character == ")" { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0
    }

    private static func shorten(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    private static func trim(_ text: String) -> String {
        var scalars = Substring(text).unicodeScalars
        while let first = scalars.first, leading.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, trailing.contains(last) { scalars.removeLast() }
        return String(scalars)
    }

    private static func clean(_ text: String) -> String {
        var title = trim(text)
        for pattern in [numbering, unreadable] {
            title = trim(pattern.stringByReplacingMatches(in: title, range: NSRange(location: 0, length: (title as NSString).length), withTemplate: ""))
        }
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.rangeOfCharacter(from: .alphanumerics) == nil ? "" : title
    }

    // Keeps the longest run of strictly rising times, so stray or repeated timestamps drop out.
    private static func ascending(_ tracks: [Track]) -> [Track] {
        guard !tracks.isEmpty else { return [] }
        var length = Array(repeating: 1, count: tracks.count), previous = Array(repeating: -1, count: tracks.count)
        for i in tracks.indices {
            for j in 0..<i where tracks[j].seconds < tracks[i].seconds && length[j] + 1 > length[i] {
                length[i] = length[j] + 1; previous[i] = j
            }
        }
        var index = length.indices.max { length[$0] < length[$1] || (length[$0] == length[$1] && $0 < $1) }!
        var result: [Track] = []
        while index >= 0 { result.append(tracks[index]); index = previous[index] }
        return result.reversed()
    }

    // Comment text from a YouTube comments response, in page order.
    static func comments(in response: Any) -> [String] {
        var texts: [String] = []
        visit(response) { object in
            if let entity = object["commentEntityPayload"] as? [String: Any],
               let properties = entity["properties"] as? [String: Any],
               let content = properties["content"] as? [String: Any],
               let text = content["content"] as? String {
                texts.append(text)
            } else if let renderer = object["commentRenderer"] as? [String: Any],
                      let runs = (renderer["contentText"] as? [String: Any])?["runs"] as? [[String: Any]] {
                texts.append(runs.compactMap { $0["text"] as? String }.joined())
            }
        }
        return texts
    }

    // The token that loads the first page of comments from a watch-page response.
    static func commentsToken(in response: Any) -> String? {
        var token: String?
        visit(response) { object in
            guard token == nil, object["sectionIdentifier"] as? String == "comment-item-section" else { return }
            token = continuationTokens(in: object).first
        }
        return token
    }

    // The token for the next page is the last item after a page of comments.
    static func nextPageToken(in response: Any) -> String? {
        var token: String?
        visit(response) { object in
            if token == nil, let items = object["continuationItems"] as? [Any], items.count > 1, let last = items.last { token = continuationTokens(in: last).first }
        }
        return token
    }

    static func description(in response: Any) -> String? {
        var text: String?
        visit(response) { object in
            if text == nil, let description = object["attributedDescription"] as? [String: Any] { text = description["content"] as? String }
        }
        return text
    }

    private static func continuationTokens(in response: Any) -> [String] {
        var tokens: [String] = []
        visit(response) { object in
            if let item = object["continuationItemRenderer"] as? [String: Any],
               let endpoint = (item["continuationEndpoint"] ?? (item["button"] as? [String: Any]).flatMap { ($0["buttonRenderer"] as? [String: Any])?["command"] }) as? [String: Any],
               let token = (endpoint["continuationCommand"] as? [String: Any])?["token"] as? String {
                tokens.append(token)
            }
        }
        return tokens
    }

    private static func visit(_ value: Any, _ body: ([String: Any]) -> Void) {
        if let object = value as? [String: Any] {
            body(object)
            for child in object.values { visit(child, body) }
        } else if let array = value as? [Any] {
            for child in array { visit(child, body) }
        }
    }
}
