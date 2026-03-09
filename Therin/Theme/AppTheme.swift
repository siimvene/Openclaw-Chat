import SwiftUI

// MARK: - Color Palette
extension Color {
    static let appBackground = Color(red: 0.059, green: 0.098, blue: 0.137) // #0F1923
    static let appBackgroundLight = Color(red: 0.961, green: 0.969, blue: 0.973) // #F5F7F8
    static let appPrimary = Color(red: 0, green: 0.482, blue: 1) // #007BFF
    
    static let glassFill = Color.white.opacity(0.03)
    static let glassBorder = Color.white.opacity(0.1)
    
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.533, green: 0.6, blue: 0.667) // ~#8899AA
    static let textMuted = Color(red: 0.42, green: 0.48, blue: 0.55) // #6B7B8D
    
    static let onlineGreen = Color(red: 0.196, green: 0.804, blue: 0.392) // #32CD64
    
    static let aiBubble = Color.white.opacity(0.03)
    static let userBubble = Color.appPrimary
}

// MARK: - Glass Panel Modifier
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 16
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

// MARK: - Message Shadow
extension View {
    func messageShadow() -> some View {
        shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Typography
extension Font {
    static let headerTitle = Font.system(size: 14, weight: .bold)
    static let headerSubtitle = Font.system(size: 11, weight: .medium)
    static let messageBody = Font.system(size: 15)
    static let timestamp = Font.system(size: 10)
    static let dateSeparator = Font.system(size: 11, weight: .semibold)
    static let inputPlaceholder = Font.system(size: 15)
}
