import Foundation

public struct RuleBasedPolisher {
    
    private struct RegexRule {
        let pattern: NSRegularExpression
        let template: String
        
        init(_ pattern: String, _ template: String, options: NSRegularExpression.Options = [.caseInsensitive]) {
            self.pattern = try! NSRegularExpression(pattern: pattern, options: options)
            self.template = template
        }
        
        func apply(to text: String) -> String {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return pattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
        }
    }
    
    // URL 与 Email 保护模式 (在规则清洗前将结构化文本提纯占位，清洗后无损还原)
    private static let protectedPattern = try! NSRegularExpression(
        pattern: #"(?:https?://[^\s，。！？、；：“”‘’<>()]+|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})"#,
        options: [.caseInsensitive]
    )
    
    // 按顺序执行的规则链
    private static let rules: [RegexRule] = [
        // 1. [中文] 纯拟声词（句首或标点后，且后面紧跟标点/空格，或连续发出）
        RegexRule("(?:^|(?<=[，。！？、；：\\s]))(?:[呃唔欸]+|[嗯啊唉噢哦诶]{2,}|[呃唔欸嗯啊唉噢哦诶]+(?=[，、\\s]))[，、\\s]*", ""),
        
        // 2. [中文] 标点锚定的独立口头禅（仅当后面紧跟逗号/顿号/空格时才删，绝不碰句中实词）
        RegexRule("(?:^|(?<=[，。！？；：\\s]))(?:那个|就是说|怎么说呢|怎么讲呢|怎么讲|那什么)[，、\\s]+", ""),
        
        // 3. [中文连词口吃] 连词在分句/句首的重复去重 (支持逗号、顿号或空格相隔)
        RegexRule("(?:^|(?<=[，。！？\\s]))(因为|所以|但是|如果|然后|就是说)(?:[，、 \\t]+\\1)+", "$1"),
        
        // 4. [中文代词口吃] 代词去重 (仅限顿号、空格相隔或直接连续卡顿，绝不跨普通逗号合并不同分句)
        RegexRule("(我|你|他|她|它|这|那|这个|那个|我们|你们|他们)(?:(?:[、 \\t]+|(?<!卿))\\1)+", "$1"),
        
        // 5. [中文机械卡顿] 连续单字卡顿（>=3次，严格排除中英文数字、日文长音符ー与常用情绪叠字）
        RegexRule("([^哈呵嘿哟啦好对行零一二三四五六七八九十百千万亿幺两壹贰叁肆伍陆柒捌玖拾佰仟0-9a-zA-Zー～~\\s，。！？,.!?])\\1{2,}", "$1"),
        
        // 6. [英文] 纯填充音 (um, uh, erm, hmm, mhm, uh-huh)
        RegexRule("\\b(?:um+|uh+|erm+|hmm+|mhm+|uh-huh)\\b[, \\t]*", ""),
        
        // 7. [英文] 标点包围的口头插入语 (e.g., ", you know," / "I mean, ")
        RegexRule("(?:^|(?<=[,.?!;\\s]))\\b(?:you know|i mean|sort of|kind of)\\b\\s*,+\\s*", ""),
        RegexRule(",\\s*\\b(?:like|basically|literally)\\b\\s*,", ","),
        
        // 8. [英文代词/介词口吃去重] (e.g., "I I", "the the", "to to")
        RegexRule("\\b(i|you|he|she|it|we|they|the|a|an|to|in|on|of|for|and|but|or|is|are|this)\\b(?:[ \\t,]+\\1\\b)+", "$1"),
        
        // 9. [日文] 常见句首/标点后填充词 (えーと、あのー、そのー、なんか)
        RegexRule("(?:^|(?<=[、。！？\\s]))(?:えー+と|えっと|あのー+|あの|そのー+|まー+)[、 \\t]+", ""),
        
        // 10. [标点与水平空格缝合] 合并删词后残留的连续逗号、清理行首孤立标点，保留段落换行
        RegexRule("[，,、]{2,}", "，"),
        RegexRule("(?m)^[，,、 \\t]+", ""),
        RegexRule("[ \\t]{2,}", " ")
    ]
    
    public static func polish(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }
        
        // 步骤 1: 提取并保护 URL 和 Email 地址 (替换为私有区域占位符)
        var protectedMatches: [String] = []
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        var maskedText = ""
        var lastOffset = trimmed.startIndex
        
        let matches = protectedPattern.matches(in: trimmed, options: [], range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: trimmed) else { continue }
            maskedText += trimmed[lastOffset..<matchRange.lowerBound]
            let matchedSubstring = String(trimmed[matchRange])
            let placeholder = "\u{E000}VBTOKEN\(protectedMatches.count)\u{E001}"
            protectedMatches.append(matchedSubstring)
            maskedText += placeholder
            lastOffset = matchRange.upperBound
        }
        maskedText += trimmed[lastOffset..<trimmed.endIndex]
        
        // 步骤 2: 按序执行清洗规则链
        var result = maskedText
        for rule in rules {
            result = rule.apply(to: result)
        }
        
        // 步骤 3: 还原受保护的 URL 与 Email 地址
        for (index, token) in protectedMatches.enumerated() {
            let placeholder = "\u{E000}VBTOKEN\(index)\u{E001}"
            result = result.replacingOccurrences(of: placeholder, with: token)
        }
        
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 步骤 4: 兜底保护——若整句清洗后只剩标点或为空，退回原文
        let strippedPunctuation = result.trimmingCharacters(in: .punctuationCharacters)
        if strippedPunctuation.isEmpty {
            return trimmed
        }
        
        return result
    }
}
