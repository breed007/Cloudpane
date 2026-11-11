import AppKit
import CloudpaneCore
import CoreText
import PDFKit

/// Lays out a ReportDocument on US Letter pages with Core Text. Core decides what the
/// report says; this only draws it, black on white, for printing and sharing.
enum ReportPDF {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54
    private static let footerHeight: CGFloat = 24

    static func render(_ document: ReportDocument) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        // Title and creator only: no author, so a shared report does not carry a name.
        let info: [CFString: Any] = [kCGPDFContextTitle: document.title, kCGPDFContextCreator: creator]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            return Data()
        }
        var page = Page(context: context)
        page.text(document.title, style: .title)
        page.text(document.subtitle, style: .note, after: 4)
        for section in document.sections {
            page.text(section.title, style: .heading, after: 20, keepWithNext: 60)
            for block in section.blocks {
                switch block {
                case .paragraph(let text): page.text(text, style: .body, after: 6)
                case .note(let text): page.text(text, style: .note, after: 6)
                case .table(let headers, let rows): page.table(headers: headers, rows: rows)
                }
            }
        }
        page.finish()
        return withoutSystemProducer(data as Data)
    }

    /// "Cloudpane 1.0" in the app; plain "Cloudpane" where the main bundle is not the app.
    static var creator: String {
        guard Bundle.main.bundleIdentifier == "com.404tools.cloudpane",
              let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { return "Cloudpane" }
        return "Cloudpane \(version)"
    }

    /// Core Graphics writes the macOS version and build into the PDF's Producer and offers no
    /// way to change it. Rewriting the document through PDFKit replaces it with "Cloudpane".
    static func withoutSystemProducer(_ data: Data) -> Data {
        guard let document = PDFDocument(data: data) else { return data }
        var attributes = document.documentAttributes ?? [:]
        attributes[PDFDocumentAttribute.producerAttribute] = "Cloudpane"
        attributes[PDFDocumentAttribute.creatorAttribute] = creator
        attributes.removeValue(forKey: PDFDocumentAttribute.authorAttribute)
        document.documentAttributes = attributes
        return document.dataRepresentation() ?? data
    }

    enum Style {
        case title, heading, body, note, header, cell

        var font: NSFont {
            switch self {
            case .title: return .systemFont(ofSize: 22, weight: .semibold)
            case .heading: return .systemFont(ofSize: 14, weight: .semibold)
            case .body: return .systemFont(ofSize: 10.5)
            case .note: return .systemFont(ofSize: 9)
            case .header: return .systemFont(ofSize: 8.5, weight: .semibold)
            case .cell: return .systemFont(ofSize: 8.5)
            }
        }

        var color: CGColor {
            switch self {
            case .note, .header: return CGColor(gray: 0.35, alpha: 1)
            default: return CGColor(gray: 0, alpha: 1)
            }
        }
    }

    static func attributed(_ text: String, _ style: Style) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): style.font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color,
        ])
    }

    /// The height text needs at a width.
    static func height(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        let setter = CTFramesetterCreateWithAttributedString(string)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(size.height)
    }

    /// The width text needs on one line.
    static func naturalWidth(_ string: NSAttributedString) -> CGFloat {
        ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil))
    }

    /// The page being drawn, with a cursor measured from the top of the content area.
    struct Page {
        let context: CGContext
        var number = 0
        var y: CGFloat = 0
        var isOpen = false
        var contentWidth: CGFloat { pageSize.width - 2 * margin }
        var bottom: CGFloat { pageSize.height - 2 * margin - footerHeight }

        init(context: CGContext) { self.context = context }

        mutating func ensure(_ height: CGFloat) {
            if !isOpen || (y + height > bottom && y > 0) { newPage() }
        }

        mutating func newPage() {
            if isOpen { endPage() }
            context.beginPDFPage(nil)
            number += 1
            y = 0
            isOpen = true
        }

        mutating func endPage() {
            let footer = attributed("Cloudpane report, page \(number)", .note)
            draw(footer, x: margin, top: pageSize.height - margin - 12, width: contentWidth, height: 14)
            context.endPDFPage()
            isOpen = false
        }

        mutating func finish() {
            if !isOpen { newPage() }
            endPage()
            context.closePDF()
        }

        /// Draws string with its top at top (from the page's top edge).
        func draw(_ string: NSAttributedString, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
            let setter = CTFramesetterCreateWithAttributedString(string)
            let rect = CGRect(x: x, y: pageSize.height - top - height, width: width, height: height)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
            CTFrameDraw(frame, context)
        }

        mutating func text(_ text: String, style: Style, after spacing: CGFloat = 0, keepWithNext: CGFloat = 0) {
            let string = attributed(text, style)
            let needed = ReportPDF.height(string, width: contentWidth)
            ensure(spacing + needed + keepWithNext)
            if y > 0 { y += spacing }
            draw(string, x: margin, top: margin + y, width: contentWidth, height: needed + 2)
            y += needed
        }

        mutating func table(headers: [String], rows: [[String]]) {
            let columns = headers.count
            guard columns > 0 else { return }
            let padding: CGFloat = 6
            let widths = columnWidths(headers: headers, rows: rows, padding: padding)
            func height(of cells: [String], _ style: Style) -> CGFloat {
                (0..<columns).map { index in
                    ReportPDF.height(attributed(index < cells.count ? cells[index] : "", style),
                                     width: widths[index] - padding)
                }.max() ?? 0
            }
            func drawRow(_ cells: [String], _ style: Style, rowHeight: CGFloat) {
                var x = margin
                for index in 0..<columns {
                    let string = attributed(index < cells.count ? cells[index] : "", style)
                    draw(string, x: x, top: margin + y, width: widths[index] - padding, height: rowHeight + 2)
                    x += widths[index]
                }
                y += rowHeight
            }
            func drawHeader() {
                drawRow(headers, .header, rowHeight: height(of: headers, .header))
                context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
                context.setLineWidth(0.5)
                let lineY = pageSize.height - margin - y - 2
                context.move(to: CGPoint(x: margin, y: lineY))
                context.addLine(to: CGPoint(x: margin + contentWidth, y: lineY))
                context.strokePath()
                y += 5
            }

            let headerHeight = height(of: headers, .header) + 5
            let firstRow = rows.first.map { height(of: $0, .cell) } ?? 0
            ensure(8 + headerHeight + firstRow)
            if y > 0 { y += 8 }
            drawHeader()
            for row in rows {
                let rowHeight = height(of: row, .cell)
                if y + rowHeight + 3 > bottom {
                    newPage()
                    drawHeader()
                }
                drawRow(row, .cell, rowHeight: rowHeight)
                y += 3
            }
        }

        /// Natural widths when they fit; otherwise narrow columns keep theirs and the wide
        /// ones share what is left in proportion to their natural width, so they wrap.
        func columnWidths(headers: [String], rows: [[String]], padding: CGFloat) -> [CGFloat] {
            let columns = headers.count
            var natural = [CGFloat](repeating: 0, count: columns)
            for index in 0..<columns {
                var widest = naturalWidth(attributed(headers[index], .header))
                for row in rows where index < row.count {
                    widest = max(widest, naturalWidth(attributed(row[index], .cell)))
                }
                natural[index] = widest + padding
            }
            let total = natural.reduce(0, +)
            if total <= contentWidth {
                let extra = (contentWidth - total) / CGFloat(columns)
                return natural.map { $0 + extra }
            }
            let share = contentWidth / CGFloat(columns)
            let narrow = natural.filter { $0 <= share }
            let wide = natural.filter { $0 > share }
            let left = contentWidth - narrow.reduce(0, +)
            let wideTotal = wide.reduce(0, +)
            return natural.map { $0 <= share ? $0 : max(left * $0 / wideTotal, 40) }
        }
    }
}
