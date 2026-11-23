import Foundation

/// One timed line of a song.
struct LyricLine: Equatable {
    /// Seconds from the start of the track.
    let time: TimeInterval
    let text: String
}

/// A parsed LRC lyric sheet.
///
/// LRC is the de-facto format for timed lyrics: `[mm:ss.xx] text`, one line per entry, with
/// optional metadata lines like `[ar:Artist]` and, in some files, several timestamps sharing a
/// single line of text for a repeated chorus.
struct SyncedLyrics: Equatable {
    let lines: [LyricLine]

    var isEmpty: Bool { lines.isEmpty }

    /// Parses an LRC document, discarding metadata tags and anything unparseable.
    /// Returns `nil` when nothing timed survives, so callers can fall back to plain lyrics.
    init?(lrc: String) {
        var parsed: [LyricLine] = []

        for raw in lrc.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let stamps = Self.timestamps(in: line)
            guard !stamps.isEmpty else { continue }

            // The text is whatever follows the last timestamp.
            let text = Self.text(after: line)
            for time in stamps {
                parsed.append(LyricLine(time: time, text: text))
            }
        }

        guard !parsed.isEmpty else { return nil }
        // LRC files are usually ordered, but a file with several timestamps per line is not.
        self.lines = parsed.sorted { $0.time < $1.time }
    }

    init(lines: [LyricLine]) {
        self.lines = lines.sorted { $0.time < $1.time }
    }

    /// The index of the line that should be showing at `position`, or `nil` before the first
    /// line starts. Binary search: this runs on every UI tick.
    func index(at position: TimeInterval) -> Int? {
        guard let first = lines.first, position >= first.time else { return nil }

        var low = 0
        var high = lines.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    func line(at position: TimeInterval) -> LyricLine? {
        index(at: position).map { lines[$0] }
    }

    // MARK: - Parsing

    /// Every `[mm:ss]`, `[mm:ss.xx]` or `[mm:ss.xxx]` at the head of a line. Metadata tags such
    /// as `[ar:Artist]` don't match, which is how they are discarded.
    private static func timestamps(in line: String) -> [TimeInterval] {
        var times: [TimeInterval] = []
        var rest = Substring(line)

        while rest.first == "[", let close = rest.firstIndex(of: "]") {
            let body = rest[rest.index(after: rest.startIndex)..<close]
            guard let time = seconds(fromTimestamp: body) else { break }
            times.append(time)
            rest = rest[rest.index(after: close)...]
        }
        return times
    }

    private static func seconds(fromTimestamp body: Substring) -> TimeInterval? {
        let parts = body.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]),
              minutes >= 0, seconds >= 0, seconds < 60
        else { return nil }
        return minutes * 60 + seconds
    }

    private static func text(after line: String) -> String {
        var rest = Substring(line)
        while rest.first == "[", let close = rest.firstIndex(of: "]") {
            guard seconds(fromTimestamp: rest[rest.index(after: rest.startIndex)..<close]) != nil
            else { break }
            rest = rest[rest.index(after: close)...]
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}
