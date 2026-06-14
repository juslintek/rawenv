import SwiftUI

/// Renders Markdown text as styled SwiftUI views.
///
/// Fixes AI-1: assistant replies containing GFM tables previously displayed as
/// raw `| pipe | text |`. This view parses the message into structural blocks
/// (``MarkdownRenderer``) and presents tables as aligned grids, headings/lists
/// as styled text, and code in a monospaced block. Inline styling (bold,
/// italic, links, inline code) is handled by `AttributedString(markdown:)`.
struct MarkdownMessageView: View {
    let text: String
    var baseFontSize: CGFloat = 13

    private var blocks: [MarkdownBlock] { MarkdownRenderer.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .accessibilityIdentifier("ai_markdown_content")
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            MarkdownInline.text(text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            MarkdownInline.text(text)
                .font(.system(size: baseFontSize))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(.system(size: baseFontSize)).foregroundStyle(Color.textMuted)
                        MarkdownInline.text(item)
                            .font(.system(size: baseFontSize))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.system(size: baseFontSize, weight: .medium))
                            .foregroundStyle(Color.textMuted)
                        MarkdownInline.text(item)
                            .font(.system(size: baseFontSize))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .codeBlock(_, let code):
            Text(code)
                .font(.system(size: baseFontSize - 1, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

        case .table(let header, let alignments, let rows):
            MarkdownTableView(
                header: header, alignments: alignments, rows: rows,
                fontSize: baseFontSize)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseFontSize + 6
        case 2: return baseFontSize + 4
        case 3: return baseFontSize + 2
        default: return baseFontSize + 1
        }
    }
}

/// A Markdown GFM table rendered as an aligned grid with a header row and
/// hairline cell separators.
struct MarkdownTableView: View {
    let header: [String]
    let alignments: [MarkdownColumnAlignment]
    let rows: [[String]]
    var fontSize: CGFloat = 13

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { idx, value in
                    cellView(value, weight: .semibold, column: idx)
                        .background(Color.bgTertiary)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { idx, value in
                        cellView(value, weight: .regular, column: idx)
                    }
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("ai_markdown_table")
    }

    private func cellView(_ raw: String, weight: Font.Weight, column: Int) -> some View {
        MarkdownInline.text(raw)
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(textAlignment(column))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: frameAlignment(column))
            .border(Color.border.opacity(0.4), width: 0.5)
    }

    private func frameAlignment(_ column: Int) -> Alignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func textAlignment(_ column: Int) -> TextAlignment {
        guard column < alignments.count else { return .leading }
        switch alignments[column] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Inline Markdown helper. Uses Foundation's `AttributedString` markdown parser
/// (bold, italic, inline code, links) and falls back to plain text on failure.
enum MarkdownInline {
    static func text(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        {
            return Text(attributed)
        }
        return Text(raw)
    }
}
