import Foundation
import CoreGraphics

/// Field plot sheet sizes for equipment planning maps.
enum PrintSheetSize: String, CaseIterable, Identifiable, Sendable {
    /// ANSI/ARCH D full sheet.
    case archD24x36
    /// Tabloid / ANSI B half-sheet class.
    case tabloid11x17
    /// ARCH B half-sheet class.
    case archB12x18

    var id: String { rawValue }

    var label: String {
        switch self {
        case .archD24x36: return "ARCH D — 24×36 in"
        case .tabloid11x17: return "Half sheet — 11×17 in"
        case .archB12x18: return "Half sheet — 12×18 in"
        }
    }

    /// Landscape print: width × height in inches.
    var widthInches: CGFloat {
        switch self {
        case .archD24x36: return 36
        case .tabloid11x17: return 17
        case .archB12x18: return 18
        }
    }

    var heightInches: CGFloat {
        switch self {
        case .archD24x36: return 24
        case .tabloid11x17: return 11
        case .archB12x18: return 12
        }
    }

    var sizePoints: CGSize {
        CGSize(width: widthInches * 72, height: heightInches * 72)
    }

    /// Suggested outer margin for plotter trim.
    var marginInches: CGFloat {
        switch self {
        case .archD24x36: return 0.5
        case .tabloid11x17, .archB12x18: return 0.4
        }
    }

    var titleBlockHeightInches: CGFloat {
        switch self {
        case .archD24x36: return 2.75
        case .tabloid11x17, .archB12x18: return 2.1
        }
    }
}
