import Testing

@testable import RawenvLib

/// Covers AI-1: GFM tables (and other block constructs) parse into structured
/// blocks instead of being left as raw pipe-delimited text.
@Suite struct MarkdownRendererTests {

    @Test func parsesTableHeaderRowsAndAlignments() {
        let md = """
            | Name  | Port  | Memory |
            |:------|:-----:|-------:|
            | pg    | 5432  | 84MB   |
            | redis | 6379  | 12MB   |
            """
        let blocks = MarkdownRenderer.parse(md)
        #expect(blocks.count == 1)
        guard case .table(let header, let alignments, let rows) = blocks[0] else {
            Issue.record("expected a table block, got \(blocks)")
            return
        }
        #expect(header == ["Name", "Port", "Memory"])
        #expect(alignments == [.leading, .center, .trailing])
        #expect(rows == [["pg", "5432", "84MB"], ["redis", "6379", "12MB"]])
    }

    @Test func tableDoesNotLeakRawPipesAsParagraph() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let blocks = MarkdownRenderer.parse(md)
        // No block should be a paragraph containing literal pipe characters.
        for block in blocks {
            if case .paragraph(let text) = block {
                #expect(!text.contains("|"))
            }
        }
        #expect(blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    @Test func tableSurroundedByText() {
        let md = """
            Here is the plan:

            | Step | Action |
            |------|--------|
            | 1    | resize |

            Done.
            """
        let blocks = MarkdownRenderer.parse(md)
        #expect(blocks.count == 3)
        #expect(blocks.first == .paragraph("Here is the plan:"))
        #expect(blocks.last == .paragraph("Done."))
        #expect(blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    @Test func parsesHeadings() {
        let blocks = MarkdownRenderer.parse("# Title\n## Subtitle")
        #expect(
            blocks == [
                .heading(level: 1, text: "Title"),
                .heading(level: 2, text: "Subtitle"),
            ])
    }

    @Test func hashWithoutSpaceIsNotHeading() {
        let blocks = MarkdownRenderer.parse("#notaheading")
        #expect(blocks == [.paragraph("#notaheading")])
    }

    @Test func parsesUnorderedList() {
        let blocks = MarkdownRenderer.parse("- one\n- two\n- three")
        #expect(blocks == [.bulletList(["one", "two", "three"])])
    }

    @Test func parsesOrderedList() {
        let blocks = MarkdownRenderer.parse("1. first\n2. second")
        #expect(blocks == [.orderedList(["first", "second"])])
    }

    @Test func parsesFencedCodeBlock() {
        let md = "```swift\nlet x = 1\n```"
        let blocks = MarkdownRenderer.parse(md)
        #expect(blocks == [.codeBlock(language: "swift", code: "let x = 1")])
    }

    @Test func plainParagraphStaysParagraph() {
        let blocks = MarkdownRenderer.parse("just some text")
        #expect(blocks == [.paragraph("just some text")])
    }

    @Test func thematicBreakIsNotTreatedAsTable() {
        // A header line with a pipe followed by a plain `---` rule (no pipe)
        // must not be misread as a table separator.
        let blocks = MarkdownRenderer.parse("a | b\n---")
        #expect(!blocks.contains { if case .table = $0 { return true } else { return false } })
    }

    @Test func handlesEscapedPipesInCells() {
        let md = "| Cmd | Note |\n|---|---|\n| a \\| b | ok |"
        let blocks = MarkdownRenderer.parse(md)
        guard case .table(_, _, let rows) = blocks[0] else {
            Issue.record("expected table")
            return
        }
        #expect(rows == [["a | b", "ok"]])
    }
}
