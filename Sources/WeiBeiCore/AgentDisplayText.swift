import Foundation

/// Agent 聊天纯文本路径的行内数学可读性归一化。
/// 富回答旧系统退役时从原富回答引擎迁出的最小必要工具：
/// 把常见 LaTeX 定界符/命令转成 Unicode，让原生 `AttributedString`
/// 在没有每条消息一个 KaTeX WKWebView 的情况下保持可读。
/// 行为与迁移前完全一致。
public enum AgentDisplayText {

    /// Hang-proof math readability for agent chat narrative.
    /// Strips common LaTeX delimiters/commands into Unicode so native
    /// `AttributedString` stays legible without per-message KaTeX WKWebView.
    public static func normalizedInlineMath(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "$$", with: "")
            .replacingOccurrences(of: #"\("#, with: "")
            .replacingOccurrences(of: #"\)"#, with: "")
            .replacingOccurrences(of: #"\["#, with: "")
            .replacingOccurrences(of: #"\]"#, with: "")

        // Pseudo display math from models: [ y_i=\hat y_i ] / multiline bracket blocks.
        if let multi = try? NSRegularExpression(pattern: #"\[\s*\n([\s\S]*?\\[A-Za-z]+[\s\S]*?)\n\s*\]"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = multi.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        if let single = try? NSRegularExpression(pattern: #"(?m)^\[\s*([^\n\]]*?\\[A-Za-z]+[^\n\]]*?)\]\s*$"#) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = single.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }

        result = replacing(
            #"\\(?:text|mathrm|operatorname|mathbf|mathit)\s*\{([^{}]+)\}"#,
            in: result,
            with: "$1"
        )
        result = replacing(
            #"\\frac\s*\{([^{}]+)\}\s*\{([^{}]+)\}"#,
            in: result,
            with: "($1)/($2)"
        )
        result = replacing(
            #"\\sqrt\s*\{([^{}]+)\}"#,
            in: result,
            with: "√($1)"
        )
        result = replacing(
            #"\\sqrt\s*([A-Za-z0-9.]+)"#,
            in: result,
            with: "√$1"
        )
        result = replacing(
            #"\\bar\s*\{\s*\\hat\s*\{?([A-Za-z])\}?\s*\}"#,
            in: result,
            with: "$1\u{0302}\u{0304}"
        )
        // Accents: \hat{y} / \hat y → ŷ
        result = replacing(#"\\hat\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0302}")
        result = replacing(#"\\hat\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0302}")
        result = replacing(#"\\bar\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0304}")
        result = replacing(#"\\bar\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0304}")
        result = replacing(#"\\tilde\s*\{([^{}]+)\}"#, in: result, with: "$1\u{0303}")
        result = replacing(#"\\tilde\s*([A-Za-z0-9])"#, in: result, with: "$1\u{0303}")
        result = replacing(#"\\vec\s*\{([^{}]+)\}"#, in: result, with: "$1\u{20D7}")
        result = replacing(#"\\vec\s*([A-Za-z0-9])"#, in: result, with: "$1\u{20D7}")

        let commandReplacements = [
            (#"\left"#, ""),
            (#"\right"#, ""),
            (#"\times"#, "×"),
            (#"\cdot"#, "·"),
            (#"\div"#, "÷"),
            (#"\sum"#, "∑"),
            (#"\prod"#, "∏"),
            (#"\int"#, "∫"),
            (#"\infty"#, "∞"),
            (#"\partial"#, "∂"),
            (#"\nabla"#, "∇"),
            (#"\rightarrow"#, "→"),
            (#"\leftarrow"#, "←"),
            (#"\Rightarrow"#, "⇒"),
            (#"\Leftarrow"#, "⇐"),
            (#"\leftrightarrow"#, "↔"),
            (#"\ldots"#, "…"),
            (#"\cdots"#, "⋯"),
            (#"\alpha"#, "α"),
            (#"\beta"#, "β"),
            (#"\gamma"#, "γ"),
            (#"\pi"#, "π"),
            (#"\sigma"#, "σ"),
            (#"\mu"#, "μ"),
            (#"\phi"#, "φ"),
            (#"\omega"#, "ω"),
            (#"\Gamma"#, "Γ"),
            (#"\Delta"#, "Δ"),
            (#"\Theta"#, "Θ"),
            (#"\Lambda"#, "Λ"),
            (#"\Sigma"#, "Σ"),
            (#"\Omega"#, "Ω"),
            (#"\delta"#, "δ"),
            (#"\theta"#, "θ"),
            (#"\lambda"#, "λ"),
            (#"\alpha"#, "α"),
            (#"\beta"#, "β"),
            (#"\gamma"#, "γ"),
            (#"\mu"#, "μ"),
            (#"\rho"#, "ρ"),
            (#"\sigma"#, "σ"),
            (#"\omega"#, "ω"),
            (#"\sum"#, "Σ"),
            (#"\infty"#, "∞"),
            (#"\qquad"#, "  "),
            (#"\quad"#, " "),
            (#"\leq"#, "≤"),
            (#"\le"#, "≤"),
            (#"\geq"#, "≥"),
            (#"\ge"#, "≥"),
            (#"\neq"#, "≠"),
            (#"\approx"#, "≈"),
            (#"\propto"#, "∝"),
            (#"\pm"#, "±"),
            (#"\,"#, ""),
            (#"\;"#, ""),
            (#"\!"#, ""),
        ]
        for (command, replacement) in commandReplacements {
            result = result.replacingOccurrences(of: command, with: replacement)
        }

        // Single-dollar inline math: $...$ (skip $$ already cleared).
        result = replacing(#"\$([^$\n]+)\$"#, in: result, with: "$1")

        result = replacing(#"\s*([≤≥≠≈∝])\s*"#, in: result, with: "$1")
        result = replacing(#"√\(([A-Za-z0-9.]+)\)"#, in: result, with: "√$1")
        result = replacing(#"\^\{([^{}]+)\}"#, in: result, with: "^$1")
        result = replacing(#"_\{([^{}]+)\}"#, in: result, with: "_$1")
        let simpleScripts = [
            (#"_0(?![A-Za-z0-9])"#, "₀"),
            (#"_1(?![A-Za-z0-9])"#, "₁"),
            (#"_2(?![A-Za-z0-9])"#, "₂"),
            (#"_3(?![A-Za-z0-9])"#, "₃"),
            (#"_4(?![A-Za-z0-9])"#, "₄"),
            (#"_5(?![A-Za-z0-9])"#, "₅"),
            (#"_6(?![A-Za-z0-9])"#, "₆"),
            (#"_7(?![A-Za-z0-9])"#, "₇"),
            (#"_8(?![A-Za-z0-9])"#, "₈"),
            (#"_9(?![A-Za-z0-9])"#, "₉"),
            (#"_i(?![A-Za-z0-9])"#, "ᵢ"),
            (#"_j(?![A-Za-z0-9])"#, "ⱼ"),
            (#"_n(?![A-Za-z0-9])"#, "ₙ"),
            (#"_t(?![A-Za-z0-9])"#, "ₜ"),
            (#"_x(?![A-Za-z0-9])"#, "ₓ"),
            (#"\^0(?![A-Za-z0-9])"#, "⁰"),
            (#"\^1(?![A-Za-z0-9])"#, "¹"),
            (#"\^2(?![A-Za-z0-9])"#, "²"),
            (#"\^3(?![A-Za-z0-9])"#, "³"),
            (#"\^4(?![A-Za-z0-9])"#, "⁴"),
            (#"\^5(?![A-Za-z0-9])"#, "⁵"),
            (#"\^6(?![A-Za-z0-9])"#, "⁶"),
            (#"\^7(?![A-Za-z0-9])"#, "⁷"),
            (#"\^8(?![A-Za-z0-9])"#, "⁸"),
            (#"\^9(?![A-Za-z0-9])"#, "⁹"),
        ]
        for (script, replacement) in simpleScripts {
            result = replacing(script, in: result, with: replacement)
        }
        return result
    }

    private static func replacing(
        _ pattern: String,
        in text: String,
        with template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: template
        )
    }
}
