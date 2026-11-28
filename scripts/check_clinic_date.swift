import Foundation

struct ClinicDateViolation: CustomStringConvertible {
    let path: String
    let line: Int
    let rule: String

    var description: String {
        "\(path):\(line): \(rule)"
    }
}

/// Replaces comments and plain string text with spaces while preserving newlines and
/// string interpolation code so line numbers stay accurate and interpolated calls are checked.
func stripCommentsAndStrings(_ source: String) -> String {
    let bytes = Array(source.utf8)
    var output: [UInt8] = []
    output.reserveCapacity(bytes.count)
    var offset = 0

    func matches(_ marker: String) -> Bool {
        let utf8 = marker.utf8
        let count = utf8.count
        return offset + count <= bytes.count
            && bytes[offset..<(offset + count)].elementsEqual(utf8)
    }

    func emitSpaces(_ count: Int = 1) {
        let end = min(bytes.count, offset + count)
        for index in offset..<end {
            output.append(bytes[index] == 10 ? 10 : 32)
        }
        offset = end
    }

    func emitRaw(_ count: Int = 1) {
        let end = min(bytes.count, offset + count)
        output.append(contentsOf: bytes[offset..<end])
        offset = end
    }

    func skipComment() -> Bool {
        if matches("//") {
            while offset < bytes.count && bytes[offset] != 10 { emitSpaces() }
            return true
        }
        guard matches("/*") else { return false }
        emitSpaces(2)
        var depth = 1
        while offset < bytes.count && depth > 0 {
            if matches("/*") {
                depth += 1
                emitSpaces(2)
            } else if matches("*/") {
                depth -= 1
                emitSpaces(2)
            } else {
                emitSpaces()
            }
        }
        return true
    }

    func skipString() -> Bool {
        var quote = offset
        while quote < bytes.count && bytes[quote] == 35 { quote += 1 }
        guard quote < bytes.count && bytes[quote] == 34 else { return false }
        let hashes = quote - offset
        emitSpaces(hashes)
        let delimiter = matches("\"\"\"") ? "\"\"\"" : "\""
        let closing = delimiter + String(repeating: "#", count: hashes)
        let escape = "\\" + String(repeating: "#", count: hashes)
        emitSpaces(delimiter.utf8.count)
        while offset < bytes.count {
            if matches(escape + "(") {
                emitSpaces(escape.utf8.count + 1)
                var depth = 1
                while offset < bytes.count && depth > 0 {
                    if skipComment() || skipString() { continue }
                    if matches("(") {
                        depth += 1
                        emitRaw()
                    } else if matches(")") {
                        depth -= 1
                        if depth == 0 {
                            emitSpaces()
                        } else {
                            emitRaw()
                        }
                    } else {
                        emitRaw()
                    }
                }
            } else if matches(escape) {
                emitSpaces(escape.utf8.count + 1)
            } else if matches(closing) {
                emitSpaces(closing.utf8.count)
                break
            } else {
                emitSpaces()
            }
        }
        return true
    }

    while offset < bytes.count {
        if skipComment() || skipString() { continue }
        emitRaw()
    }
    return String(decoding: output, as: UTF8.self)
}

func lineNumber(at index: String.Index, in text: String) -> Int {
    var line = 1
    var cursor = text.startIndex
    while cursor < index {
        if text[cursor] == "\n" { line += 1 }
        cursor = text.index(after: cursor)
    }
    return line
}

struct Rule {
    let pattern: NSRegularExpression
    let message: String

    init(_ regex: String, message: String) throws {
        self.pattern = try NSRegularExpression(pattern: regex)
        self.message = message
    }
}

let rules: [Rule] = try [
    Rule(
        #"\bautoupdatingCurrent\b"#,
        message: "Do not use autoupdatingCurrent; use ClinicDate."),
    Rule(
        #"\b(Calendar|Locale|TimeZone)\s*\.\s*current\b"#,
        message: "Do not use device .current calendar, locale, or time zone; use ClinicDate."),
    Rule(
        #"\bisDateInToday\b"#,
        message: "Do not use isDateInToday; compare against clinicToday with isSameDayAs."),
    Rule(
        #"\.formatted\s*\(\s*(\.dateTime\b|\.interval\b|date\s*:)"#,
        message: "Use ClinicDate.formatStyle or ClinicDate.intervalFormatStyle for date formatting."
    ),
    Rule(
        #"\bformat\s*:\s*(\.dateTime\b|\.interval\b)"#,
        message: "Use ClinicDate.formatStyle or ClinicDate.intervalFormatStyle in Text formatters."
    ),
    Rule(
        #"@Dependency\s*\(\s*\\\.(calendar|locale)\s*\)"#,
        message: "Do not inject device calendar or locale in production code; use ClinicDate."),
]

let roots = ["Sources", "ClinicalShared", "ClinicalWidget", "clinical-swift"]
let manager = FileManager.default
var violations: [ClinicDateViolation] = []

for folder in roots {
    guard let enumerator = manager.enumerator(atPath: folder) else {
        FileHandle.standardError.write(Data("Missing required source folder: \(folder)\n".utf8))
        exit(1)
    }
    var files: [String] = []
    for case let item as String in enumerator where item.hasSuffix(".swift") {
        files.append(folder + "/" + item)
    }
    for path in files.sorted() {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let stripped = stripCommentsAndStrings(source)
        let range = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        for rule in rules {
            for match in rule.pattern.matches(in: stripped, range: range) {
                guard let swiftRange = Range(match.range, in: stripped) else { continue }
                violations.append(
                    ClinicDateViolation(
                        path: path,
                        line: lineNumber(at: swiftRange.lowerBound, in: stripped),
                        rule: rule.message
                    ))
            }
        }
    }
}

violations.sort { ($0.path, $0.line, $0.rule) < ($1.path, $1.line, $1.rule) }

if !violations.isEmpty {
    for violation in violations {
        print(violation)
    }
    exit(1)
}

print("ClinicDate checks passed.")
