import Foundation

public struct LyricWord: Equatable {
    public let start: Double
    public let duration: Double
    public let text: String
    public init(start: Double, duration: Double, text: String) {
        self.start = start; self.duration = duration; self.text = text
    }
}

public struct LyricLine: Equatable {
    public let start: Double
    public let text: String
    public let words: [LyricWord]
    public init(start: Double, text: String, words: [LyricWord] = []) {
        self.start = start; self.text = text; self.words = words
    }
}

public struct LyricsDocument: Equatable {
    public let lines: [LyricLine]
    public init(lines: [LyricLine]) { self.lines = lines }

    public func currentLineIndex(at t: Double) -> Int {
        var idx = -1
        for (i, l) in lines.enumerated() where l.start <= t { idx = i }
        return idx
    }

    public static func parseLRC(_ raw: String) -> LyricsDocument {
        var out: [LyricLine] = []
        for line in raw.components(separatedBy: .newlines) {
            let times = lrcTimes(line)
            let text = line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !times.isEmpty else { continue }
            for t in times { out.append(LyricLine(start: t, text: text)) }
        }
        return LyricsDocument(lines: out.sorted { $0.start < $1.start })
    }

    public static func parseKRC(_ raw: String) -> LyricsDocument {
        let lineRe = try! NSRegularExpression(pattern: #"\[(\d{3,7}),(\d{3,7})\]((?:<\d{1,6},\d{1,6},\d{1,2}>[^\n\[]*)+)"#)
        let wordRe = try! NSRegularExpression(pattern: #"<(\d{1,6}),(\d{1,6}),\d{1,2}>([^\n<]*)"#)
        let ns = raw as NSString
        var out: [LyricLine] = []
        lineRe.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.range(at: 1).location != NSNotFound, m.range(at: 3).location != NSNotFound else { return }
            let startMs = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let body = ns.substring(with: m.range(at: 3))
            let bns = body as NSString
            var words: [LyricWord] = []
            var text = ""
            wordRe.enumerateMatches(in: body, range: NSRange(location: 0, length: bns.length)) { wm, _, _ in
                guard let wm, wm.range(at: 3).location != NSNotFound else { return }
                let off = Double(bns.substring(with: wm.range(at: 1))) ?? 0
                let dur = Double(bns.substring(with: wm.range(at: 2))) ?? 0
                let w = bns.substring(with: wm.range(at: 3))
                words.append(LyricWord(start: (startMs + off) / 1000, duration: dur / 1000, text: w))
                text += w
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(LyricLine(start: startMs / 1000, text: trimmed, words: words)) }
        }
        return LyricsDocument(lines: out.sorted { $0.start < $1.start })
    }

    public func toLRC() -> String {
        lines.map { String(format: "[%02d:%02d.%02d]%@", Int($0.start) / 60, Int($0.start) % 60, Int(($0.start * 100).rounded()) % 100, $0.text) }
            .joined(separator: "\n")
    }

    private static func lrcTimes(_ line: String) -> [Double] {
        var result: [Double] = []
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = line as NSString
        regex.enumerateMatches(in: line, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
            var frac = 0.0
            if m.range(at: 3).location != NSNotFound {
                let fs = ns.substring(with: m.range(at: 3))
                frac = (Double(fs) ?? 0) / pow(10, Double(fs.count))
            }
            result.append(mm * 60 + ss + frac)
        }
        return result
    }
}
