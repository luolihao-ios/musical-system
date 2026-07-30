import Foundation

enum LRCParser {
    private static let pattern =
        #"\[(\d{1,3}):(\d{2})(?:\.(\d{2,3}))?\]"#

    static func parse(_ source: String) -> [LyricLine] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        var result: [(order: Int, line: LyricLine)] = []
        var order = 0
        for rawLine in source.split(
            omittingEmptySubsequences: true,
            whereSeparator: { $0.isNewline }
        ) {
            let line = String(rawLine)
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let text = regex.stringByReplacingMatches(
                in: line,
                range: range,
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minutesRange]),
                      let seconds = Double(line[secondsRange]) else {
                    continue
                }
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let rawFraction = String(line[fractionRange])
                    if let value = Double(rawFraction) {
                        fraction = value / (rawFraction.count == 2 ? 100 : 1_000)
                    }
                }
                result.append(
                    (
                        order,
                        LyricLine(
                            timestamp: minutes * 60 + seconds + fraction,
                            text: text
                        )
                    )
                )
                order += 1
            }
        }
        return result.sorted {
            if $0.line.timestamp == $1.line.timestamp {
                return $0.order < $1.order
            }
            return $0.line.timestamp < $1.line.timestamp
        }.map(\.line)
    }

    static func currentIndex(
        lines: [LyricLine],
        position: TimeInterval
    ) -> Int? {
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let middle = low + (high - low) / 2
            if lines[middle].timestamp <= position {
                result = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        return result
    }
}
