import CloudpaneCore
import SwiftUI

/// A small Markdown renderer for exactly what the help pages use: headings, paragraphs,
/// bullet and numbered lists, simple tables, and inline bold, code and links. Adapted from
/// the help renderer in another 404 Tools app. Inline spans go through AttributedString's
/// Markdown parser; the block structure is parsed here. Links to `.md` files are handed to onOpenTopic, so a
/// cross-reference switches pages instead of opening a browser; the link keeps its anchor,
/// and each heading carries its anchor as its id so a page can scroll to it. Colors are the
/// system's, so pages follow the app's dark appearance.
struct MarkdownView: View {
    let markdown: String
    var onOpenTopic: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            let link = url.absoluteString
            let path = link.split(separator: "#").first.map(String.init) ?? ""
            if link.hasPrefix("#") || url.scheme == nil || path.hasSuffix(".md") {
                onOpenTopic(link)
                return .handled
            }
            return .systemAction
        })
    }

    // MARK: - Block model

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbered([String])
        case table(header: [String], rows: [[String]])
    }

    private var blocks: [Block] {
        var result: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var index = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                result.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph.removeAll()
            }
        }

        func numberedItem(_ line: String) -> String? {
            guard let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                  line[line.index(after: dot)...].hasPrefix(" ") else { return nil }
            return String(line[line.index(dot, offsetBy: 2)...])
        }

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
            } else if trimmed.hasPrefix("### ") {
                flushParagraph(); result.append(.heading(level: 3, text: String(trimmed.dropFirst(4)))); index += 1
            } else if trimmed.hasPrefix("## ") {
                flushParagraph(); result.append(.heading(level: 2, text: String(trimmed.dropFirst(3)))); index += 1
            } else if trimmed.hasPrefix("# ") {
                flushParagraph(); result.append(.heading(level: 1, text: String(trimmed.dropFirst(2)))); index += 1
            } else if trimmed.hasPrefix("- ") {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    items.append(String(lines[index].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    index += 1
                }
                result.append(.bullets(items))
            } else if numberedItem(trimmed) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = numberedItem(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                result.append(.numbered(items))
            } else if trimmed.hasPrefix("|") {
                flushParagraph()
                var tableLines: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                if let table = parseTable(tableLines) { result.append(table) }
            } else {
                paragraph.append(trimmed)
                index += 1
            }
        }
        flushParagraph()
        return result
    }

    private func parseTable(_ lines: [String]) -> Block? {
        func cells(_ row: String) -> [String] {
            var parts = row.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.first == "" { parts.removeFirst() }
            if parts.last == "" { parts.removeLast() }
            return parts
        }
        guard lines.count >= 2 else { return nil }
        return .table(header: cells(lines[0]), rows: lines.dropFirst(2).map(cells))
    }

    // MARK: - Rendering

    @ViewBuilder
    private func render(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level == 1 ? .title.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, level == 1 ? 0 : 8)
                .id(HelpCatalog.slug(text))
        case .paragraph(let text):
            inline(text).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            list(items.map { ("•", $0) })
        case .numbered(let items):
            list(items.enumerated().map { ("\($0.offset + 1).", $0.element) })
        case .table(let header, let rows):
            tableView(header: header, rows: rows)
        }
    }

    private func list(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.0).foregroundStyle(.secondary).monospacedDigit()
                    inline(item.1).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tableView(header: [String], rows: [[String]]) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
                ForEach(header.indices, id: \.self) { column in
                    inline(header[column]).font(.callout.weight(.semibold))
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { row in
                GridRow {
                    ForEach(rows[row].indices, id: \.self) { column in
                        inline(rows[row][column]).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }
}
