import Foundation

/// Replaces sensitive value spans in place. Unchanged HTML and JSON stay byte-for-byte identical;
/// parsing and re-encoding the entire document would destroy the original response formatting.
enum SupportDiagnosticBodyRedactor {
    static func redact(
        _ text: String,
        isSensitiveKey: (String) -> Bool,
        sanitizeString: (String) -> String = { $0 }
    ) -> String {
        let bytes = Array(text.utf8)
        var result = [UInt8]()
        var copiedThrough = 0
        var cursor = 0
        while cursor < bytes.count {
            guard bytes[cursor] == 34, let end = stringEnd(bytes, from: cursor) else {
                cursor += 1
                continue
            }
            let token = Data(bytes[cursor..<end])
            guard let decoded = try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed]) as? String else {
                cursor = end
                continue
            }
            var next = end
            while next < bytes.count, isWhitespace(bytes[next]) { next += 1 }
            if next < bytes.count, bytes[next] == 58 {
                next += 1
                while next < bytes.count, isWhitespace(bytes[next]) { next += 1 }
                if isSensitiveKey(decoded), next < bytes.count {
                    let valueEnd = endOfValue(bytes, from: next)
                    result.append(contentsOf: bytes[copiedThrough..<next])
                    result.append(contentsOf: "\"<redacted>\"".utf8)
                    copiedThrough = valueEnd
                    cursor = valueEnd
                    continue
                }
            } else {
                let sanitized = sanitizeString(decoded)
                if sanitized != decoded,
                   let replacement = try? JSONSerialization.data(withJSONObject: sanitized, options: [.fragmentsAllowed, .withoutEscapingSlashes]) {
                    result.append(contentsOf: bytes[copiedThrough..<cursor])
                    result.append(contentsOf: replacement)
                    copiedThrough = end
                }
            }
            cursor = end
        }
        result.append(contentsOf: bytes[copiedThrough...])
        return redactHTMLInputs(String(decoding: result, as: UTF8.self), isSensitiveKey: isSensitiveKey)
    }

    private static func stringEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var cursor = start + 1
        while cursor < bytes.count {
            if bytes[cursor] == 92 { cursor += 2; continue }
            if bytes[cursor] == 34 { return cursor + 1 }
            cursor += 1
        }
        return nil
    }

    private static func endOfValue(_ bytes: [UInt8], from start: Int) -> Int {
        if bytes[start] == 34 { return stringEnd(bytes, from: start) ?? bytes.count }
        if bytes[start] == 123 || bytes[start] == 91 {
            var depth = 0
            var cursor = start
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 34:
                    cursor = stringEnd(bytes, from: cursor) ?? bytes.count
                    continue
                case 123, 91: depth += 1
                case 125, 93:
                    depth -= 1
                    if depth == 0 { return cursor + 1 }
                default: break
                }
                cursor += 1
            }
            return bytes.count
        }
        var cursor = start
        while cursor < bytes.count, !isWhitespace(bytes[cursor]), ![UInt8(44), 125, 93].contains(bytes[cursor]) {
            cursor += 1
        }
        return cursor
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 13
    }

    private static func redactHTMLInputs(_ text: String, isSensitiveKey: (String) -> Bool) -> String {
        guard text.range(of: "<input", options: .caseInsensitive) != nil,
              let tags = try? NSRegularExpression(pattern: #"(?i)<input\b[^>]*>"#),
              let names = try? NSRegularExpression(pattern: #"(?i)\b(?:name|id)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#),
              let values = try? NSRegularExpression(pattern: #"(?i)\bvalue\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return text }
        var output = text
        for tagMatch in tags.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let tagRange = Range(tagMatch.range, in: output) else { continue }
            var tag = String(output[tagRange])
            let range = NSRange(tag.startIndex..., in: tag)
            let sensitive = names.matches(in: tag, range: range).contains { match in
                (1..<match.numberOfRanges).contains { index in
                    guard let range = Range(match.range(at: index), in: tag) else { return false }
                    return isSensitiveKey(String(tag[range]))
                }
            }
            guard sensitive else { continue }
            for match in values.matches(in: tag, range: range).reversed() {
                for index in 1..<match.numberOfRanges {
                    if let valueRange = Range(match.range(at: index), in: tag) {
                        tag.replaceSubrange(valueRange, with: "&lt;redacted&gt;")
                        break
                    }
                }
            }
            output.replaceSubrange(tagRange, with: tag)
        }
        return output
    }
}
