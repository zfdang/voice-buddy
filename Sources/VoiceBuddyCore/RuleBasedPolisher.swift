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
    
    // 按顺序执行的规则链
    private static let rules: [RegexRule] = [
        // 1. [中文] 纯拟声词（句首或标点后，且后面紧跟标点/空格，或连续发出）
        RegexRule("(?:^|(?<=[，。！？、；：\\s]))(?:[呃唔欸]+|[嗯啊唉噢哦诶]{2,}|[呃唔欸嗯啊唉噢哦诶]+(?=[，、\\s]))[，、\\s]*", ""),
        
        // 2. [中文] 标点锚定的独立口头禅（仅当后面紧跟逗号/顿号时才删，绝不碰句中实词）
        RegexRule("(?:^|(?<=[，。！？；：\\s]))(?:那个|就是说|怎么说呢|怎么讲呢|怎么讲|那什么)[，、\\s]+", ""),
        
        // 3. [中文] 高频代词与虚词口吃去重（保护“讨论讨论”等正常ABAB词，仅合并代词/连词重复）
        RegexRule("(我|你|他|她|它|这|那|这个|那个|就是|然后|因为|所以|但是|如果|我们|你们|他们|的|了|是|在)(?:[，、\\s]*\\1)+", "$1"),
        
        // 4. [中文] 任意单字连续机械卡顿（>=3次，排除 哈/呵/嘿/哟/啦/好/对/行/6/2/3 等正常叠字与热切回应）
        RegexRule("([^哈呵嘿哟啦好对行623a-zA-Z0-9\\s，。！？,.!?])\\1{2,}", "$1"),
        
        // 5. [英文] 纯填充音 (um, uh, erm, hmm, mhm, uh-huh)
        RegexRule("\\b(?:um+|uh+|erm+|hmm+|mhm+|uh-huh)\\b[,\\s]*", ""),
        
        // 6. [英文] 标点包围的口头插入语 (e.g., ", you know," / "I mean, ")
        RegexRule("(?:^|(?<=[,.?!;\\s]))\\b(?:you know|i mean|sort of|kind of)\\b\\s*,+\\s*", ""),
        RegexRule(",\\s*\\b(?:like|basically|literally)\\b\\s*,", ","),
        
        // 7. [英文] 常见代词/冠词/介词口吃去重 (e.g., "I I", "the the", "to to")
        RegexRule("\\b(i|you|he|she|it|we|they|the|a|an|to|in|on|of|for|and|but|or|is|are|this)\\b(?:[\\s,]+\\1\\b)+", "$1"),
        
        // 8. [日文] 常见句首/标点后填充词 (えーと、あのー、そのー、なんか)
        RegexRule("(?:^|(?<=[、。！？\\s]))(?:えー+と|えっと|あのー+|あの|そのー+|まー+)[、\\s]+", ""),
        
        // 9. [标点与空格缝合] 合并删词后残留的连续逗号、清理句首孤立标点
        RegexRule("[，,、]{2,}", "，"),
        RegexRule("^[，,、\\s]+", ""),
        RegexRule("\\s{2,}", " ")
    ]
    
    public static func polish(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return input }
        
        var result = trimmed
        for rule in rules {
            result = rule.apply(to: result)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 兜底保护：如果整句话只说了“嗯。”或“Uh”，清洗后只剩标点或为空，则退回原文
        let strippedPunctuation = result.trimmingCharacters(in: .punctuationCharacters)
        if strippedPunctuation.isEmpty {
            return trimmed
        }
        
        return result
    }
}
