import Foundation

/// Column alignment parsed from a GitHub-flavored Markdown table delimiter row
/// (`:---`, `:---:`, `---:`).
public enum MarkdownColumnAlignment: Equatable, Sendable {
    case leading
    case center
    case trailing
}

/// A structural piece of Markdown produced by ``MarkdownRenderer``.
///
/// LLM and canned assistant replies routinely contain tables, headings, lists,
/// and code. Rendering the raw string left tables as literal pipe characters
/// (bug AI-1). Parsing into blocks lets the view present each as a styled
/// element — tables become real grids, not `| pipe | text |`.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([String])
    case orderedList([String])
    case codeBlock(language: String?, code: String)
    case table(header: [String], alignments: [MarkdownColumnAlignment], rows: [[String]])
}

/// Minimal, dependency-free GitHub-flavored Markdown block parser.
///
/// It intentionally handles only the structural constructs SwiftUI cannot
/// render on its own — tables, headings, lists, and fenced code. Inline
/// styling (bold, italic, links, inline code) is left to the view layer via
/// `AttributedString(markdown:)`, which already supports it.
public enum MarkdownRenderer {

    /// Parses `text` into an ordered list of ``MarkdownBlock`` values.
    public static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            let joined = paragraph
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block: ``` ... ```
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count,
                      !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1 // consume the closing fence (if present)
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang,
                                         code: code.joined(separator: "\n")))
                continue
            }

            // GFM table: a header row followed by a delimiter row.
            if trimmed.contains("|"),
               i + 1 < lines.count,
               isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = splitRow(trimmed)
                let alignments = normalizeAlignments(parseAlignments(lines[i + 1]),
                                                     to: header.count)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if rowLine.isEmpty || !rowLine.contains("|") { break }
                    rows.append(normalizeRow(splitRow(rowLine), to: header.count))
                    i += 1
                }
                blocks.append(.table(header: header, alignments: alignments, rows: rows))
                continue
            }

            // Blank line terminates the current paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // ATX heading: # .. ######
            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            // Unordered list.
            if isBullet(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isBullet(t) else { break }
                    items.append(bulletContent(t))
                    i += 1
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Ordered list.
            if isOrdered(trimmed) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isOrdered(t) else { break }
                    items.append(orderedContent(t))
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            // Default: accumulate into the running paragraph.
            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: - Tables

    /// Splits a table row on unescaped pipes, dropping the optional leading and
    /// trailing pipe and trimming each cell.
    static func splitRow(_ line: String) -> [String] {
        let placeholder = "\u{0001}" // sentinel for escaped pipes
        var s = line.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\|", with: placeholder)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map {
            $0.replacingOccurrences(of: placeholder, with: "|")
              .trimmingCharacters(in: .whitespaces)
        }
    }

    /// True when `line` is a Markdown table delimiter row such as
    /// `|---|:--:|---:|`. Requires a pipe so a plain `---` horizontal rule is
    /// not mistaken for a table.
    static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let cells = splitRow(trimmed)
        guard !cells.isEmpty else { return false }
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard isSeparatorCell(c) else { return false }
        }
        return true
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        guard !cell.isEmpty else { return false }
        var body = cell
        if body.hasPrefix(":") { body.removeFirst() }
        if body.hasSuffix(":") { body.removeLast() }
        guard !body.isEmpty else { return false }
        return body.allSatisfy { $0 == "-" }
    }

    static func parseAlignments(_ line: String) -> [MarkdownColumnAlignment] {
        splitRow(line).map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            let left = t.hasPrefix(":")
            let right = t.hasSuffix(":")
            switch (left, right) {
            case (true, true): return .center
            case (false, true): return .trailing
            default: return .leading
            }
        }
    }

    private static func normalizeAlignments(_ alignments: [MarkdownColumnAlignment],
                                            to count: Int) -> [MarkdownColumnAlignment] {
        if alignments.count == count { return alignments }
        if alignments.count > count { return Array(alignments.prefix(count)) }
        return alignments + Array(repeating: .leading, count: count - alignments.count)
    }

    private static func normalizeRow(_ row: [String], to count: Int) -> [String] {
        if row.count == count { return row }
        if row.count > count { return Array(row.prefix(count)) }
        return row + Array(repeating: "", count: count - row.count)
    }

    // MARK: - Headings & lists

    static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = line.dropFirst(level)
        // A real heading needs a space after the hashes (or be empty).
        guard rest.isEmpty || rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    static func bulletContent(_ line: String) -> String {
        String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    static func isOrdered(_ line: String) -> Bool {
        orderedSeparatorIndex(line) != nil
    }

    static func orderedContent(_ line: String) -> String {
        guard let idx = orderedSeparatorIndex(line) else { return line }
        return String(line[idx...]).trimmingCharacters(in: .whitespaces)
    }

    /// Returns the index just past the `N.` / `N)` marker of an ordered list
    /// item, or `nil` when the line is not an ordered list item.
    private static func orderedSeparatorIndex(_ line: String) -> String.Index? {
        var idx = line.startIndex
        var sawDigit = false
        while idx < line.endIndex, line[idx].isNumber {
            sawDigit = true
            idx = line.index(after: idx)
        }
        guard sawDigit, idx < line.endIndex else { return nil }
        guard line[idx] == "." || line[idx] == ")" else { return nil }
        let afterMarker = line.index(after: idx)
        guard afterMarker < line.endIndex, line[afterMarker] == " " else { return nil }
        return afterMarker
    }
}
