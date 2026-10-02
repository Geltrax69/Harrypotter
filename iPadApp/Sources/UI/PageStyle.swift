import SwiftUI
import UIKit

/// Shared page grid. Answer baselines land on these rules.
enum PageGrid {
    nonisolated static let lineSpacing: CGFloat = 44
    nonisolated static let marginX: CGFloat = 56
}

/// The paper the page is printed on. Persisted by raw value.
enum PaperStyle: String, CaseIterable, Identifiable {
    case royal, ruled, grid, dotted, plain

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .royal: return "Royal Folio"
        case .ruled: return "Ruled Notebook"
        case .grid: return "Grid Notebook"
        case .dotted: return "Dotted Journal"
        case .plain: return "Plain Paper"
        }
    }

    var symbol: String {
        switch self {
        case .royal: return "crown"
        case .ruled: return "text.justify"
        case .grid: return "squareshape.split.3x3"
        case .dotted: return "circle.grid.3x3"
        case .plain: return "doc"
        }
    }
}

/// A script the answer is written in. `size`/`lines` were tuned so each font
/// reads at notebook scale; `lines` is how many rules one line of text spans.
/// `isFreeLicense` is false for fonts that are personal-use only (demo
/// licenses) and need a commercial license before any public release.
enum AnswerFont: String, CaseIterable, Identifiable {
    case cedarville, justAnotherHand, cinzel, awesome, crustaceans
    case brittany, amsterdam, alwaysClassy, priestacy, amsterdamHandwriting

    var id: String { rawValue }

    var spec: (name: String, postScript: String, size: CGFloat, lines: Int, isFreeLicense: Bool) {
        switch self {
        case .cedarville: return ("Cedarville", "Cedarville-Cursive", 36, 1, true)
        case .justAnotherHand: return ("Just Another Hand", "JustAnotherHand-Regular", 40, 1, true)
        case .cinzel: return ("Cinzel Decorative", "CinzelDecorative-Regular", 21, 1, true)
        case .awesome: return ("Awesome", "AwesomeRegular", 32, 1, false)
        case .crustaceans: return ("Crustaceans", "CrustaceansSignatureDEMO-Reg", 42, 1, false)
        case .brittany: return ("Brittany", "BrittanySignatureScriptRegular", 50, 2, false)
        case .amsterdam: return ("Amsterdam", "Amsterdam", 32, 2, false)
        case .alwaysClassy: return ("Always Classy", "AlwaysClassy-Regular", 42, 2, false)
        case .priestacy: return ("Priestacy", "Priestacy", 56, 2, false)
        case .amsterdamHandwriting: return ("Amsterdam Hand", "AmsterdamHandwriting-Regular", 46, 2, false)
        }
    }

    var displayName: String { spec.name }

    var uiFont: UIFont {
        UIFont(name: spec.postScript, size: spec.size) ?? .italicSystemFont(ofSize: 26)
    }

    /// Baseline-to-baseline distance, a whole number of rules.
    var linePitch: CGFloat { CGFloat(spec.lines) * PageGrid.lineSpacing }
}

/// Royal, magical theme roles on top of the base palette.
extension Palette {
    /// Burnished gold for chrome accents and answer ink in the dark.
    static let gold = Color(
        light: Color(red: 0.55, green: 0.40, blue: 0.12),
        dark: Color(red: 0.88, green: 0.74, blue: 0.45)
    )
    /// Answer ink: gold leaf by night, royal violet ink by day.
    static let answerInk = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.76, blue: 0.47, alpha: 1)
            : UIColor(red: 0.27, green: 0.16, blue: 0.48, alpha: 1)
    }
    /// The glow around freshly written answer ink.
    static let answerGlow = UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.82, blue: 0.45, alpha: 0.55)
            : UIColor(red: 0.55, green: 0.40, blue: 0.85, alpha: 0.25)
    }
    /// Midnight-velvet sheet (dark) / warm vellum (light).
    static let royalSheet = Color(
        light: Color(red: 0.965, green: 0.937, blue: 0.871),
        dark: Color(red: 0.075, green: 0.063, blue: 0.118)
    )
    static let royalSheetGlow = Color(
        light: Color(red: 1.0, green: 0.98, blue: 0.93),
        dark: Color(red: 0.17, green: 0.12, blue: 0.27)
    )
}

extension Font {
    /// Cinzel Decorative for royal chrome; falls back to a serif.
    static func royal(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "CinzelDecorative-Bold" : "CinzelDecorative-Regular", size: size)
    }
}
