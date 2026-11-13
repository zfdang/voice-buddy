import Foundation

/// Resolves only explicit hour/weekday corrections; uncertain wording stays with the model.
public enum ExplicitCorrections {
    private static let number = "[零〇一二两三四五六七八九十0-9]{1,3}"
    private static let cue = #"[，,、\s]*(?:啊|哦|呃|嗯)?(?:不对|说错了|改成)[，,、\s]*(?:应该)?(?:是)?[，,、\s]*"#
    private static let day = "今天|明天|后天|昨天|前天"
    private static let period = "凌晨|早上|上午|中午|下午|晚上"
    private static let hourPattern = "(?<d1>\(day))?(?<p1>\(period))?(?<a>\(number))点(?:钟)?\(cue)(?<d2>\(day))?(?<p2>\(period))?(?<b>\(number))点(?<clock>钟)?"
    private static let weekPattern = "(?<a>(?:周|星期)[一二三四五六日天])\(cue)(?<b>(?:周|星期)[一二三四五六日天])"

    private static func value(_ name: String, _ match: NSTextCheckingResult, _ text: String) -> String {
        guard let range = Range(match.range(withName: name), in: text) else { return "" }
        return String(text[range])
    }

    public static func resolve(_ text: String) -> String {
        var output = text
        for _ in 0..<4 {
            let previous = output
            for (pattern, isHour) in [(hourPattern, true), (weekPattern, false)] {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let input = output
                for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed() {
                    guard let range = Range(match.range, in: output) else { continue }
                    let replacement: String
                    if isHour {
                        guard let old = integer(value("a", match, input)), let new = integer(value("b", match, input)), (0...23).contains(old), (0...23).contains(new) else { continue }
                        let oldDay = value("d1", match, input), newDay = value("d2", match, input)
                        let oldPeriod = value("p1", match, input), newPeriod = value("p2", match, input)
                        replacement = (newDay.isEmpty ? oldDay : newDay) + (newPeriod.isEmpty ? oldPeriod : newPeriod) + value("b", match, input) + "点" + value("clock", match, input)
                    } else {
                        replacement = value("b", match, input)
                    }
                    output.replaceSubrange(range, with: replacement)
                }
            }
            if output == previous { break }
        }
        return output
    }

    /// A style rewrite may change formatting, but must not lose or revive corrected hour values.
    public static func unsafeReason(_ output: String, original: String) -> String? {
        let resolved = resolve(original)
        guard resolved != original else { return nil }
        let expected = hours(resolved), before = hours(original), actual = hours(output)
        // Check all resolved hours as the old/new pair can share a 12-hour representation.
        if !expected.isSubset(of: actual) { return "Resolved time was lost" }
        if !actual.intersection(before.subtracting(expected)).isEmpty { return "Superseded time was reintroduced" }
        let relativeDays = [("今天", "今日"), ("明天", "明日"), ("后天", "后日"), ("昨天", "昨日"), ("前天", "前日")]
        for (spoken, written) in relativeDays where resolved.contains(spoken) || resolved.contains(written) {
            if !output.contains(spoken) && !output.contains(written) { return "Relative date was lost" }
        }
        let expectedDays = weekdays(resolved), oldDays = weekdays(original), actualDays = weekdays(output)
        if !expectedDays.isSubset(of: actualDays) { return "Resolved weekday was lost" }
        if !actualDays.intersection(oldDays.subtracting(expectedDays)).isEmpty { return "Superseded weekday was reintroduced" }
        return nil
    }

    private static func integer(_ text: String) -> Int? {
        if let value = Int(text) { return value }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let ten = text.firstIndex(of: "十") {
            let left = String(text[..<ten]), right = String(text[text.index(after: ten)...])
            guard left.count <= 1, right.count <= 1 else { return nil }
            guard let tens = left.isEmpty ? 1 : left.first.flatMap({ digits[$0] }), let units = right.isEmpty ? 0 : right.first.flatMap({ digits[$0] }) else { return nil }
            return tens * 10 + units
        }
        return text.count == 1 ? text.first.flatMap { digits[$0] } : nil
    }

    private static func hours(_ text: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: "(\(number))点|([0-2]?[0-9]):[0-5][0-9]") else { return [] }
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let group = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let range = Range(match.range(at: group), in: text), let hour = integer(String(text[range])) else { return nil }
            return hour % 12
        })
    }

    private static func weekdays(_ text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "(?:周|星期)([一二三四五六日天])") else { return [] }
        return Set(regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let day = String(text[range]); return day == "天" ? "日" : day
        })
    }
}
