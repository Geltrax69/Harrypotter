import SwiftUI

/// Living Graphite Folio palette + type roles. Quiet cool mineral-paper sheet,
/// graphite input, deep indigo for response and status. Colors are defined
/// against light/dark so dark mode is first-class. No parchment, no ornament.
enum Palette {
    /// The sheet the page is written on: cool mineral paper.
    static let sheet = Color(
        light: Color(red: 0.957, green: 0.961, blue: 0.968),
        dark: Color(red: 0.086, green: 0.094, blue: 0.106)
    )
    /// A slightly recessed sheet edge / margin.
    static let sheetEdge = Color(
        light: Color(red: 0.902, green: 0.910, blue: 0.925),
        dark: Color(red: 0.129, green: 0.137, blue: 0.153)
    )
    /// Graphite: the ink the user writes with and primary text.
    static let graphite = Color(
        light: Color(red: 0.161, green: 0.173, blue: 0.196),
        dark: Color(red: 0.878, green: 0.886, blue: 0.902)
    )
    /// Secondary graphite for supporting labels.
    static let graphiteSoft = Color(
        light: Color(red: 0.388, green: 0.408, blue: 0.447),
        dark: Color(red: 0.612, green: 0.627, blue: 0.659)
    )
    /// Deep indigo: response text and status accent.
    static let indigo = Color(
        light: Color(red: 0.208, green: 0.235, blue: 0.451),
        dark: Color(red: 0.541, green: 0.573, blue: 0.831)
    )
    static let indigoSoft = Color(
        light: Color(red: 0.208, green: 0.235, blue: 0.451).opacity(0.10),
        dark: Color(red: 0.541, green: 0.573, blue: 0.831).opacity(0.16)
    )
}

extension Palette {
    /// Graphite as PencilKit ink. PencilKit inverts ink for dark mode itself,
    /// so it must receive the light-appearance color, never the dynamic one.
    static let graphiteInk = UIColor(graphite).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
