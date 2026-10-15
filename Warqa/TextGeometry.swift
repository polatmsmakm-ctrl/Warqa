import SwiftUI
import UIKit
import CoreText

/// يحوّل النص (عربي أو إنجليزي) إلى مسار حروف، حتى نقدر نرسمه عادي أو منقّط.
enum TextGeometry {
    static let baseSize: CGFloat = 100
    private static var cache: [String: CGPath] = [:]

    static func basePath(text: String, design: TextDesign) -> CGPath {
        let key = design.rawValue + "|" + text
        if let cached = cache[key] { return cached }
        let path = build(text: text, design: design)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = path
        return path
    }

    static func size(text: String, design: TextDesign, fontSize: Double) -> CGSize {
        let box = basePath(text: text, design: design).boundingBoxOfPath
        if box.isNull || box.width < 1 || box.height < 1 {
            return CGSize(width: 80, height: 80)
        }
        let scale = CGFloat(fontSize) / baseSize
        return CGSize(width: box.width * scale, height: box.height * scale)
    }

    private static func build(text: String, design: TextDesign) -> CGPath {
        let font = design.uiFont(size: baseSize)
        let lineHeight = baseSize * 1.35
        let lines = text.components(separatedBy: "\n")

        struct LineData {
            var line: CTLine
            var width: CGFloat
            var index: Int
        }

        var items: [LineData] = []
        for (index, string) in lines.enumerated() where !string.isEmpty {
            let attributed = NSAttributedString(string: string, attributes: [.font: font])
            let ctLine = CTLineCreateWithAttributedString(attributed)
            let width = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
            items.append(LineData(line: ctLine, width: width, index: index))
        }

        let maxWidth = items.map { $0.width }.max() ?? 0
        let result = CGMutablePath()

        for item in items {
            let xOffset = (maxWidth - item.width) / 2
            let lineY = CGFloat(item.index) * lineHeight
            let runs = CTLineGetGlyphRuns(item.line) as! [CTRun]
            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let fontValue = attributes[kCTFontAttributeName as String] else { continue }
                let runFont = fontValue as! CTFont
                let count = CTRunGetGlyphCount(run)
                if count == 0 { continue }
                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRangeMake(0, 0), &glyphs)
                CTRunGetPositions(run, CFRangeMake(0, 0), &positions)
                for i in 0..<count {
                    guard let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                    let transform = CGAffineTransform(
                        a: 1, b: 0, c: 0, d: -1,
                        tx: positions[i].x + xOffset,
                        ty: lineY - positions[i].y
                    )
                    result.addPath(glyphPath, transform: transform)
                }
            }
        }

        let box = result.boundingBoxOfPath
        if box.isNull { return CGMutablePath() }
        var move = CGAffineTransform(translationX: -box.minX, y: -box.minY)
        return result.copy(using: &move) ?? result
    }
}

struct TextShape: Shape {
    var text: String
    var design: TextDesign

    func path(in rect: CGRect) -> Path {
        let base = TextGeometry.basePath(text: text, design: design)
        let box = base.boundingBoxOfPath
        guard !box.isNull, box.width > 0, box.height > 0 else { return Path() }
        let scale = min(rect.width / box.width, rect.height / box.height)
        let ox = rect.minX + (rect.width - box.width * scale) / 2
        let oy = rect.minY + (rect.height - box.height * scale) / 2
        var transform = CGAffineTransform(translationX: ox, y: oy).scaledBy(x: scale, y: scale)
        guard let moved = base.copy(using: &transform) else { return Path() }
        return Path(moved)
    }
}

struct ArrowShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let head = min(r.height * 0.9, r.width * 0.45)
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.move(to: CGPoint(x: r.maxX - head, y: r.midY - head / 2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX - head, y: r.midY + head / 2))
        return p
    }
}

struct LineShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
