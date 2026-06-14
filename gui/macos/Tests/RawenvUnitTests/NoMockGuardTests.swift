import Foundation
import Testing

@testable import RawenvLib

/// Guard suite that locks in the de-mock work: the shipping app sources under
/// `gui/macos/Sources` must not contain simulation/mock markers in code, and
/// every `Task.sleep` must carry an explanatory comment so reviewers can tell
/// real async work apart from UI pacing.
///
/// Markers (`simulate`, `fake`, `mock`) and unexplained sleeps are tolerated
/// only inside comments. Mock-prefixed test doubles belong under `Tests/`,
/// which this suite never scans.
@Suite struct NoMockGuardTests {

    // MARK: - Source discovery

    /// `gui/macos/Sources`, derived from this test file's location so the scan
    /// works regardless of the current working directory.
    static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)  // .../Tests/RawenvUnitTests/NoMockGuardTests.swift
            .deletingLastPathComponent()  // .../Tests/RawenvUnitTests
            .deletingLastPathComponent()  // .../Tests
            .deletingLastPathComponent()  // .../macos
            .appendingPathComponent("Sources")
    }

    static func swiftSourceFiles() -> [URL] {
        let root = sourcesDirectory
        guard
            let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil)
        else { return [] }
        var files: [URL] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Path relative to `Sources/` for readable failure messages.
    static func relativePath(_ url: URL) -> String {
        let base = sourcesDirectory.path
        return url.path.hasPrefix(base)
            ? String(url.path.dropFirst(base.count).drop(while: { $0 == "/" }))
            : url.lastPathComponent
    }

    // MARK: - Comment stripping

    /// A source file with comments removed but line structure preserved, so we
    /// can reason about "code outside comments" line-by-line. String literals
    /// (single-line and triple-quoted) are kept, since a marker hardcoded in a
    /// string is just as much of a smell as one in an identifier.
    struct Stripped {
        let rawLines: [String]
        /// Per line: the code with comment text removed.
        let codeLines: [String]
        /// Per line: whether the original line contained any comment characters.
        let hadComment: [Bool]
        /// Per line: whether the line was entirely a comment (no code).
        let isCommentOnly: [Bool]
    }

    static func strip(_ source: String) -> Stripped {
        enum Mode { case code, string, multilineString, lineComment, blockComment }
        var mode: Mode = .code

        let raw = source.components(separatedBy: "\n")
        var codeLines: [String] = []
        var hadComment: [Bool] = []
        var commentOnly: [Bool] = []

        for line in raw {
            let chars = Array(line)
            var code = ""
            var sawComment = false
            var i = 0

            func peek(_ offset: Int) -> Character? {
                let idx = i + offset
                return idx < chars.count ? chars[idx] : nil
            }

            while i < chars.count {
                let c = chars[i]
                switch mode {
                case .code:
                    if c == "\"", peek(1) == "\"", peek(2) == "\"" {
                        code.append("\"\"\"")
                        mode = .multilineString
                        i += 3
                    } else if c == "/", peek(1) == "/" {
                        sawComment = true
                        mode = .lineComment
                        i = chars.count  // rest of the line is a comment
                    } else if c == "/", peek(1) == "*" {
                        sawComment = true
                        mode = .blockComment
                        i += 2
                    } else if c == "\"" {
                        code.append(c)
                        mode = .string
                        i += 1
                    } else {
                        code.append(c)
                        i += 1
                    }
                case .string:
                    code.append(c)
                    if c == "\\" {
                        if let n = peek(1) {
                            code.append(n)
                            i += 2
                        } else {
                            i += 1
                        }
                    } else if c == "\"" {
                        mode = .code
                        i += 1
                    } else {
                        i += 1
                    }
                case .multilineString:
                    if c == "\"", peek(1) == "\"", peek(2) == "\"" {
                        code.append("\"\"\"")
                        mode = .code
                        i += 3
                    } else {
                        code.append(c)
                        i += 1
                    }
                case .lineComment:
                    i += 1  // consumed; rest of line skipped above
                case .blockComment:
                    sawComment = true
                    if c == "*", peek(1) == "/" {
                        mode = .code
                        i += 2
                    } else {
                        i += 1
                    }
                }
            }

            if mode == .lineComment { mode = .code }  // comments end at newline

            let trimmedRaw = line.trimmingCharacters(in: .whitespaces)
            let trimmedCode = code.trimmingCharacters(in: .whitespaces)
            codeLines.append(code)
            hadComment.append(sawComment)
            commentOnly.append(!trimmedRaw.isEmpty && trimmedCode.isEmpty && sawComment)
        }

        return Stripped(
            rawLines: raw, codeLines: codeLines,
            hadComment: hadComment, isCommentOnly: commentOnly)
    }

    // MARK: - Tests

    @Test func sourcesDirectoryExists() {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: Self.sourcesDirectory.path, isDirectory: &isDir)
        #expect(
            exists && isDir.boolValue,
            "Could not locate Sources at \(Self.sourcesDirectory.path)")
        #expect(!Self.swiftSourceFiles().isEmpty, "No Swift sources found to scan")
    }

    /// No `simulate` / `fake` / `mock` (case-insensitive) in code outside comments.
    /// Mock-prefixed names are allowed only under `Tests/`, which is never scanned.
    @Test func noSimulationMarkersOutsideComments() throws {
        let markers = ["simulate", "fake", "mock"]
        var violations: [String] = []

        for file in Self.swiftSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let stripped = Self.strip(source)
            for (index, code) in stripped.codeLines.enumerated() {
                let lower = code.lowercased()
                for marker in markers where lower.contains(marker) {
                    violations.append(
                        "\(Self.relativePath(file)):\(index + 1): '\(marker)' in code -> "
                            + stripped.rawLines[index].trimmingCharacters(in: .whitespaces))
                }
            }
        }

        #expect(
            violations.isEmpty,
            "Simulation/mock markers found in app source (move to Tests/ or remove):\n\(violations.joined(separator: "\n"))"
        )
    }

    /// Every `Task.sleep` in app source must be explained by a comment, so an
    /// intentional UI-pacing delay can't be mistaken for hidden fake work.
    @Test func noUnexplainedTaskSleep() throws {
        var violations: [String] = []

        for file in Self.swiftSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            let stripped = Self.strip(source)
            for (index, code) in stripped.codeLines.enumerated() where code.contains("Task.sleep") {
                if Self.isExplained(at: index, in: stripped) { continue }
                violations.append(
                    "\(Self.relativePath(file)):\(index + 1): "
                        + stripped.rawLines[index].trimmingCharacters(in: .whitespaces))
            }
        }

        #expect(
            violations.isEmpty,
            "Unexplained Task.sleep found (add a comment explaining the delay, or remove it):\n\(violations.joined(separator: "\n"))"
        )
    }

    /// A `Task.sleep` is "explained" when its own line carries a comment, or the
    /// nearest preceding non-blank line is a comment.
    static func isExplained(at index: Int, in stripped: Stripped) -> Bool {
        if stripped.hadComment[index] { return true }
        var j = index - 1
        while j >= 0 {
            if stripped.rawLines[j].trimmingCharacters(in: .whitespaces).isEmpty {
                j -= 1
                continue
            }
            return stripped.isCommentOnly[j]
        }
        return false
    }
}
