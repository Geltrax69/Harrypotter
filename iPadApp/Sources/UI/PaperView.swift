import UIKit

/// The page itself, living INSIDE the scrolling canvas (behind the user's ink)
/// so paper and answers scroll with the writing for free.
///
/// - Paper pattern is a tiled pattern color (no giant backing store, so the
///   page can grow without bound).
/// - Each answer is its own small view that writes itself in, left to right,
///   line by line, in the chosen script, with every baseline on a rule.
final class PaperView: UIView {
    private var paper: PaperStyle?
    private var isDark = false
    private let margins = [UIView(), UIView()]
    private var answerViews: [UUID: AnswerTextView] = [:]

    /// Lowest point any answer occupies.
    private(set) var contentBottom: CGFloat = 0
    /// Bottom of the last line currently being revealed (to follow while writing).
    private(set) var revealBottom: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        margins.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        paper: PaperStyle,
        isDark: Bool,
        answers: [PageAnswer],
        revealed: Int,
        font: AnswerFont,
        pageWidth: CGFloat
    ) {
        if paper != self.paper || isDark != self.isDark {
            self.paper = paper
            self.isDark = isDark
            backgroundColor = Self.pattern(for: paper, dark: isDark)
            styleMargins(paper: paper, dark: isDark)
        }
        layoutMargins(height: bounds.height)

        // Sync answer views with the model.
        let ids = Set(answers.map(\.id))
        for (id, view) in answerViews where !ids.contains(id) {
            view.removeFromSuperview()
            answerViews[id] = nil
        }
        var bottom: CGFloat = 0
        revealBottom = nil
        for (index, answer) in answers.enumerated() {
            let view = answerViews[answer.id] ?? {
                let v = AnswerTextView()
                addSubview(v)
                answerViews[answer.id] = v
                return v
            }()
            let isLast = index == answers.count - 1
            view.configure(
                answer: answer,
                font: font,
                maxX: pageWidth - 40,
                revealed: isLast ? revealed : .max
            )
            bottom = max(bottom, view.frame.maxY)
            if isLast, revealed != .max { revealBottom = view.revealBottom }
        }
        contentBottom = bottom
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutMargins(height: bounds.height)
    }

    // MARK: - Paper

    private func layoutMargins(height: CGFloat) {
        let x = PageGrid.marginX
        margins[0].frame = CGRect(x: x, y: 0, width: 1, height: height)
        margins[1].frame = CGRect(x: x + 4, y: 0, width: 1, height: height)
    }

    private func styleMargins(paper: PaperStyle, dark: Bool) {
        let color: UIColor
        switch paper {
        case .royal: color = dark ? UIColor(red: 0.88, green: 0.74, blue: 0.45, alpha: 0.35) : UIColor(red: 0.62, green: 0.16, blue: 0.20, alpha: 0.45)
        case .ruled: color = UIColor(red: 0.85, green: 0.30, blue: 0.32, alpha: dark ? 0.45 : 0.55)
        default: color = .clear
        }
        margins[0].backgroundColor = color
        // Royal gets a double margin rule.
        margins[1].backgroundColor = paper == .royal ? color : .clear
    }

    /// One tile of the paper pattern, as a pattern color. Tiles start at the
    /// page origin, so horizontal rules fall exactly on multiples of the grid.
    private static func pattern(for paper: PaperStyle, dark: Bool) -> UIColor {
        let s = PageGrid.lineSpacing
        let line: UIColor
        switch paper {
        case .royal: line = dark ? UIColor(red: 0.88, green: 0.74, blue: 0.45, alpha: 0.16) : UIColor(red: 0.55, green: 0.40, blue: 0.12, alpha: 0.22)
        case .ruled: line = dark ? UIColor(red: 0.45, green: 0.62, blue: 0.95, alpha: 0.22) : UIColor(red: 0.30, green: 0.50, blue: 0.85, alpha: 0.30)
        default: line = dark ? UIColor(white: 1, alpha: 0.13) : UIColor(white: 0, alpha: 0.14)
        }
        let size: CGSize
        switch paper {
        case .grid: size = CGSize(width: s / 2, height: s / 2)
        case .dotted: size = CGSize(width: s / 2, height: s / 2)
        default: size = CGSize(width: 8, height: s)
        }
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            line.setFill()
            switch paper {
            case .royal, .ruled:
                ctx.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
            case .grid:
                ctx.fill(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1))
                ctx.fill(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height))
            case .dotted:
                let line2 = line.withAlphaComponent(min(1, line.cgColor.alpha * 2.2))
                line2.setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: size.width - 2, y: size.height - 2, width: 2.4, height: 2.4))
            case .plain:
                break
            }
        }
        return UIColor(patternImage: image)
    }
}

/// One answer, laid out on the rules and revealed character by character.
final class AnswerTextView: UIView {
    private struct Line { let text: String; let baseline: CGFloat; let start: Int }

    private var lines: [Line] = []
    private var font: UIFont = .systemFont(ofSize: 20)
    private var revealed = Int.max
    private var key: String = ""
    private static let pad: CGFloat = 24

    /// Bottom of the line holding the reveal cursor, in page coordinates.
    var revealBottom: CGFloat {
        let line = lines.last { $0.start <= revealed } ?? lines.first
        return frame.minY + (line?.baseline ?? 0) - font.descender + Self.pad
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(answer: PageAnswer, font answerFont: AnswerFont, maxX: CGFloat, revealed: Int) {
        let newKey = "\(answer.id)|\(answerFont.rawValue)|\(maxX)"
        if newKey != key {
            key = newKey
            font = answerFont.uiFont
            layOut(answer: answer, pitch: answerFont.linePitch, maxX: maxX)
            setNeedsDisplay()
        }
        if revealed != self.revealed {
            let old = self.revealed
            self.revealed = revealed
            // Redraw only the line(s) the reveal cursor moved across; the glow
            // makes full redraws costly at 30 updates a second.
            if old == .max || revealed == .max || revealed < old {
                setNeedsDisplay()
            } else {
                for line in lines where line.start < revealed && line.start + line.text.count >= old {
                    setNeedsDisplay(CGRect(x: 0, y: line.baseline - font.ascender - Self.pad,
                                           width: bounds.width, height: font.lineHeight + Self.pad * 2))
                }
            }
        }
    }

    /// Greedy word wrap; first baseline is the first rule clear of the
    /// question, every following baseline one pitch lower (always on a rule).
    private func layOut(answer: PageAnswer, pitch: CGFloat, maxX: CGFloat) {
        let rule = PageGrid.lineSpacing
        let x = answer.origin.x
        let width = max(maxX - x, 160)
        let firstBaseline = ((answer.origin.y + font.ascender * 0.75) / rule).rounded(.up) * rule
        let attrs: [NSAttributedString.Key: Any] = [.font: font]

        var result: [(String, Int)] = []
        var current = ""
        var currentStart = 0
        var cursor = 0
        for word in answer.text.split(separator: " ", omittingEmptySubsequences: false) {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if !current.isEmpty, (candidate as NSString).size(withAttributes: attrs).width > width {
                result.append((current, currentStart))
                current = String(word)
                currentStart = cursor
            } else {
                current = candidate
            }
            cursor += word.count + 1
        }
        if !current.isEmpty { result.append((current, currentStart)) }

        let pad = Self.pad
        let top = firstBaseline - font.ascender - pad
        lines = result.enumerated().map { i, item in
            Line(text: item.0, baseline: firstBaseline + CGFloat(i) * pitch - top, start: item.1)
        }
        let lastBaseline = (lines.last?.baseline ?? 0) + top
        frame = CGRect(
            x: x - pad,
            y: top,
            width: width + pad * 2,
            height: lastBaseline - font.descender + pad - top
        )
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // A soft glow makes the ink feel freshly conjured.
        ctx.setShadow(offset: .zero, blur: 7, color: Palette.answerGlow.resolvedColor(with: traitCollection).cgColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Palette.answerInk.resolvedColor(with: traitCollection),
        ]
        for line in lines where line.start < revealed {
            let visible = revealed == .max ? line.text : String(line.text.prefix(revealed - line.start))
            (visible as NSString).draw(at: CGPoint(x: Self.pad, y: line.baseline - font.ascender), withAttributes: attrs)
        }
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        setNeedsDisplay()
    }
}
