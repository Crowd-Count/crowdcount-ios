import SwiftUI
import UIKit

extension UIColor {
    static func fromColor(_ color: Color) -> UIColor {
        switch color {
        case .red:
            return UIColor(red: 255/255, green: 59/255, blue: 48/255, alpha: 1.0)
        case .orange:
            return UIColor(red: 255/255, green: 149/255, blue: 0/255, alpha: 1.0)
        case .yellow:
            return UIColor(red: 255/255, green: 204/255, blue: 0/255, alpha: 1.0)
        case .green:
            return UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1.0)
        case .mint:
            return UIColor(red: 0/255, green: 199/255, blue: 190/255, alpha: 1.0)
        case .teal:
            return UIColor(red: 48/255, green: 176/255, blue: 199/255, alpha: 1.0)
        case .cyan:
            return UIColor(red: 50/255, green: 173/255, blue: 230/255, alpha: 1.0)
        case .blue:
            return UIColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)
        case .indigo:
            return UIColor(red: 88/255, green: 86/255, blue: 214/255, alpha: 1.0)
        case .purple:
            return UIColor(red: 175/255, green: 82/255, blue: 222/255, alpha: 1.0)
        case .pink:
            return UIColor(red: 255/255, green: 45/255, blue: 85/255, alpha: 1.0)
        case .brown:
            return UIColor(red: 162/255, green: 132/255, blue: 94/255, alpha: 1.0)
        case .primary:
            return UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? .white : .black
            }
        default:
            return UIColor.gray
        }
    }
}

extension Color {
    static func fromString(_ color: String) -> Color {
        switch color.lowercased() {
        case "red":
            return .red
        case "orange":
            return .orange
        case "yellow":
            return .yellow
        case "green":
            return .green
        case "mint":
            return .mint
        case "teal":
            return .teal
        case "cyan":
            return .cyan
        case "blue":
            return .blue
        case "indigo":
            return .indigo
        case "purple":
            return .purple
        case "pink":
            return .pink
        case "brown":
            return .brown
        case "primary":
            return .primary
        default:
            print("Unknown color string: \(color). Defaulting to gray.")
            return .gray
        }
    }
    
    func uiColor() -> UIColor {
        return UIColor.fromColor(self)
    }
}
