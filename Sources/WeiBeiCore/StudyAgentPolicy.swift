import Foundation

public enum StudyAgentPurpose: String, Codable, Sendable {
    case conversation
    case quietInsight
}

public enum StudyAgentWorkflow: String, Codable, Sendable {
    case automatic
    case studyCompanion
    case courseWayfinding
    case closeReading
    case noteMaking
    case recallPractice
}

public enum StudyAgentAnswerFormPolicy: String, Codable, Equatable, Sendable {
    case automatic
    case textOnly
    case partialRichAllowed
}

public enum StudyAgentSourceLimitation {
    public static func isHonest(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let limitationTerms = [
            "没有", "缺少", "不足", "无法", "不能", "未提供", "无可读", "缺失", "尚未",
            "no readable", "no source", "missing", "insufficient", "cannot", "can't", "unable",
        ]
        let evidenceTerms = [
            "材料", "来源", "证据", "数据", "原文", "文档", "内容", "上下文",
            "material", "source", "evidence", "data", "document", "context",
        ]
        let unsupportedClaimTerms = [
            "安全剂量为", "安全剂量是", "建议剂量为", "建议剂量是", "推荐剂量",
            "可以服用", "应服用", "病因是", "诊断为", "我估计", "推测为", "大约为", "约为",
            "safe dose is", "recommended dose", "should take", "diagnosis is", "i estimate",
        ]
        let containsQuantifiedClaim = normalized.range(
            of: #"\d+(?:\.\d+)?\s*(?:mg|g|ml|mcg|μg|%|毫克|克|毫升|微克)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return limitationTerms.contains(where: normalized.contains)
            && evidenceTerms.contains(where: normalized.contains)
            && !unsupportedClaimTerms.contains(where: normalized.contains)
            && !containsQuantifiedClaim
    }
}

public enum StudyAgentQuestionScope {
    public static func allowsSourceFreeAnswer(_ question: String) -> Bool {
        var remainder = normalized(question)
        let sourceFreePhrases = [
            "请给我讲一个笑话", "给我讲一个笑话", "请给我讲个笑话", "给我讲个笑话",
            "讲一个笑话", "讲个笑话", "说一个笑话", "说个笑话",
            "你叫什么名字", "你的名字是什么", "你叫什么", "你是谁",
            "介绍一下你自己", "自我介绍一下", "你能做什么", "你可以做什么",
            "你会做什么", "你是干什么的",
            "早上好", "下午好", "晚上好", "你好", "您好", "哈喽", "嗨", "在吗",
            "连通测试", "连接测试", "连通复核", "连接复核", "只回复", "仅回复", "pi订阅登录已连通",
            "不要生成富回答", "不生成富回答", "不要用富回答",
            "谢谢你", "谢谢", "多谢", "明白了", "知道了", "收到", "好的", "再见",
            "tellmeajoke", "tellajoke", "whatisyourname", "whatsyourname", "whoareyou",
            "introduceyourself", "whatcanyoudo", "hello", "hi", "hey", "thankyou", "thanks", "goodbye", "bye",
        ].sorted { $0.count > $1.count }
        var matchedSourceFreePhrase = false
        for phrase in sourceFreePhrases where remainder.contains(phrase) {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
            matchedSourceFreePhrase = true
        }
        guard matchedSourceFreePhrase else { return false }
        let benignWords = [
            "请", "一下", "可以吗", "行吗", "呀", "啊", "呢", "吧", "嘛", "哈",
            "候选包", "当前包", "本次", "本轮", "版本",
            "please", "me", "a", "the", "and",
        ]
        for word in benignWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        remainder.removeAll { $0.isNumber }
        return remainder.isEmpty
    }

    public static func allowsLearningOnlyAnswer(_ question: String) -> Bool {
        var remainder = normalized(question)
        let statePhrases = [
            "你记得我的学习情况吗", "你记得我学到哪吗", "我上次学习到哪了", "我上次学习到哪",
            "我上次学到哪了", "我上次学到哪", "上次学习到哪了", "上次学习到哪",
            "上次学到哪了", "上次学到哪", "我的学习进度", "学习进度", "我的学习目标", "学习目标",
            "我的目标", "我的学习困惑", "学习困惑", "我的困惑", "接下来学什么",
            "接下来做什么", "下一步学什么", "下一步做什么", "下一步", "你记得我吗",
            "wheredidistoplasttime", "whereididstoplasttime", "learningprogress", "mygoal", "mylearninggoal",
            "myconfusion", "whatnext", "doyourememberme",
        ]
        var matchedStatePhrase = false
        for phrase in statePhrases where remainder.contains(phrase) {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
            matchedStatePhrase = true
        }
        guard matchedStatePhrase else { return false }
        let benignWords = [
            "请告诉我一下", "请告诉我", "告诉我一下", "告诉我", "我", "的", "是", "什么",
            "有哪些", "请", "一下", "了", "吗", "呢", "和", "以及", "位置", "在哪", "哪里",
            "当前", "现在", "想", "要", "please", "tellme", "the", "and", "location",
            "current", "now", "what", "is", "are", "my", "i", "did", "lasttime",
        ]
        for word in benignWords {
            remainder = remainder.replacingOccurrences(of: word, with: "")
        }
        return remainder.isEmpty
    }

    private static func normalized(_ question: String) -> String {
        question.lowercased().unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.map(String.init).joined()
    }
}

public enum StudyAgentRichAnswerRequest {
    public static func isExplicit(_ question: String) -> Bool {
        let normalized = question.lowercased()
        let choiceTerms = [
            "自行选择最合适的回答形态", "自行选择回答形态", "选择最合适的回答形态",
            "只有交互或可视关系", "不要为了展示能力硬做", "无需富回答", "不需要富回答", "不要富回答",
            "choose the best answer format", "choose the most suitable answer format",
            "only generate a rich answer when", "do not force a rich answer", "no rich answer needed",
        ]
        guard !choiceTerms.contains(where: normalized.contains) else { return false }

        let requestTerms = [
            "用富回答", "用可调的富回答", "给我富回答", "生成富回答", "做成富回答", "以富回答", "富回答形式",
            "做成可调", "给个可调", "做成可交互", "给个可交互", "做个交互", "做个互动",
            "用图示", "画个函数图", "画出函数图", "做个关系图", "做个时间线", "时间线展示",
            "做个图像叠层", "做个模拟", "做个实验", "实验演示", "演示这个实验",
            "use a rich answer", "give me a rich answer", "generate a rich answer", "rich answer format",
            "make it interactive", "show an interactive", "interactive timeline", "with a diagram", "draw a function graph", "show a relationship graph",
            "show a timeline", "show an image overlay", "run a simulation", "show an experiment",
            "run an experiment",
        ]
        return requestTerms.contains(where: normalized.contains)
    }
}

public enum StudyAgentResolutionEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard StudyAgentCurrentTurnEvidence.matches(evidence, question: question),
              let statement = statement(in: evidence) else { return false }
        let value = statement.lowercased()
        let unresolvedTerms = [
            "不懂", "不理解", "不会", "没懂", "仍然困惑", "还是困惑", "不知道", "不能区分", "不能够",
            "还不能", "尚不能", "无法", "没法", "尚未", "还没", "并不", "不太", "不确定",
            "不正确", "并非正确", "答错", "错误", "不对",
            "don't understand", "do not understand", "can't", "cannot", "still confused", "not sure",
            "not able", "unable", "not yet", "have not", "haven't", "incorrect", "not correct", "wrong answer", "is wrong",
        ]
        guard !unresolvedTerms.contains(where: value.contains) else { return false }
        let questionTerms = ["什么", "为什么", "怎么", "为何", "吗", "？", "?", "what", "why", "how"]
        guard !questionTerms.contains(where: value.contains) else { return false }
        let masteryTerms = [
            "懂了", "明白了", "会了", "掌握了", "可以区分", "能够区分", "能解释", "答对", "正确",
            "解决了", "不再困惑", "understand now", "got it", "can distinguish", "can explain", "correct",
        ]
        if masteryTerms.contains(where: value.contains) { return true }
        let answerMarkers = [
            "是", "指", "因为", "所以", "而", "但是", "扣除", "等于", "相比", "表示", "反映", "意味着", "即", "=",
            " is ", " means", "because", "therefore", "while", "equals", "represents", "reflects", "differs",
        ]
        guard answerMarkers.contains(where: value.contains) else { return false }
        let meaningfulCount = statement.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        return meaningfulCount >= 12
    }

    private static func statement(in evidence: String) -> String? {
        let prefixes = ["[用户：本轮]", "[会话：当前]"]
        guard let prefix = prefixes.first(where: { evidence.hasPrefix($0) }) else { return nil }
        let quoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")
        let value = String(evidence.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

}

public enum StudyAgentCurrentTurnEvidence {
    public static func matches(_ evidence: String, question: String) -> Bool {
        guard let statement = statement(in: evidence), statement.count >= 2 else { return false }
        if statement.count < 4 {
            return normalized(statement) == normalized(question)
        }
        var searchStart = question.startIndex
        while searchStart < question.endIndex,
              let range = question.range(of: statement, range: searchStart..<question.endIndex) {
            if hasClauseBoundaries(range, in: question),
               !omitsLeadingNegation(range, in: question) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func hasClauseBoundaries(_ range: Range<String.Index>, in question: String) -> Bool {
        let startsAtBoundary = range.lowerBound == question.startIndex
            || question[question.index(before: range.lowerBound)].isWhitespace
            || question[question.index(before: range.lowerBound)].isPunctuation
        let endsAtBoundary = range.upperBound == question.endIndex
            || question[range.upperBound].isWhitespace
            || question[range.upperBound].isPunctuation
        return startsAtBoundary && endsAtBoundary
    }

    private static func omitsLeadingNegation(
        _ range: Range<String.Index>,
        in question: String
    ) -> Bool {
        guard range.lowerBound > question.startIndex else { return false }
        let prefix = String(question[..<range.lowerBound]).lowercased()
        let immediate = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["不", "没", "未", "无", "别", "勿"].contains(where: immediate.hasSuffix) {
            return true
        }
        let clause = prefix
            .components(separatedBy: CharacterSet(charactersIn: "，,。！？；;:：.!?"))
            .last ?? prefix
        let negativePhrases = [
            "不想", "不喜欢", "不太", "不能", "不会", "不要", "不愿", "没有", "没法", "尚未", "还没", "并不", "并非",
            " not ", " never ", " no ", " without ", "cannot", "can't", "don't", "doesn't", "didn't",
        ]
        let paddedClause = " \(clause) "
        return negativePhrases.contains(where: paddedClause.contains)
    }

    private static func statement(in evidence: String) -> String? {
        let prefixes = ["[用户：本轮]", "[会话：当前]"]
        guard let prefix = prefixes.first(where: { evidence.hasPrefix($0) }) else { return nil }
        let quoteCharacters = CharacterSet(charactersIn: "\"'“”‘’")
        let value = String(evidence.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: quoteCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalized(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
    }
}
