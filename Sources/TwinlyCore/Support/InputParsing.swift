import Foundation

public struct EnvParseError: Error, Equatable, LocalizedError {
    public let line: Int
    public let reason: String
    public var errorDescription: String? {
        reason.hasPrefix("isn't") ? "Line \(line) \(reason)" : "Line \(line): \(reason)"
    }
}

public enum InputParsing {
    /// Splits a command-line string into arguments. Supports 'single', "double" quotes and backslash escapes.
    public static func tokenizeArguments(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inToken = false
        var quote: Character? = nil
        var escaping = false

        for ch in input {
            if escaping {
                current.append(ch)
                escaping = false
                inToken = true
                continue
            }
            if let q = quote {
                if ch == q {
                    quote = nil
                } else if ch == "\\" && q == "\"" {
                    escaping = true
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case "\\":
                escaping = true
                inToken = true
            case "'", "\"":
                quote = ch
                inToken = true
            case " ", "\t", "\n":
                if inToken {
                    tokens.append(current)
                    current = ""
                    inToken = false
                }
            default:
                current.append(ch)
                inToken = true
            }
        }
        if escaping { current.append("\\") }
        if inToken { tokens.append(current) }
        return tokens
    }

    /// Inverse of `tokenizeArguments`.
    public static func formatArguments(_ args: [String]) -> String {
        args.map { arg -> String in
            if arg.isEmpty { return "\"\"" }
            let needsQuoting = arg.contains { " \t\n\"'\\".contains($0) }
            guard needsQuoting else { return arg }
            if !arg.contains("\"") && !arg.contains("\\") { return "\"\(arg)\"" }
            return arg.map { ch -> String in
                " \t\n\"'\\".contains(ch) ? "\\\(ch)" : String(ch)
            }.joined()
        }.joined(separator: " ")
    }

    /// Parses `KEY=value` lines. Blank lines and `#` comments are skipped.
    public static func parseEnvironment(_ input: String) -> Result<[String: String], EnvParseError> {
        var result: [String: String] = [:]
        let lines = input.components(separatedBy: .newlines)
        for (idx, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else {
                return .failure(EnvParseError(line: idx + 1, reason: "isn't KEY=value."))
            }
            let key = String(line[line.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...])
            guard ShellEnvironment.isValidEnvName(key) else {
                return .failure(EnvParseError(line: idx + 1, reason: key.isEmpty ? "isn't KEY=value." : "“\(key)” isn't a valid variable name."))
            }
            result[key] = value
        }
        return .success(result)
    }

    public static func formatEnvironment(_ env: [String: String]) -> String {
        env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
    }
}
