import SwiftUI
import UIKit

extension Color {
    static let fsRed = Color(red: 0xD9 / 255, green: 0x00 / 255, blue: 0x0D / 255)
    static let fsTeal = Color(red: 0x00 / 255, green: 0x81 / 255, blue: 0x83 / 255)
}

extension UIColor {
    static let fsRed = UIColor(red: 0xD9 / 255, green: 0, blue: 0x0D / 255, alpha: 1)
    static let fsTeal = UIColor(red: 0, green: 0x81 / 255, blue: 0x83 / 255, alpha: 1)
}

/// "fs PDF IQ" wordmark — red fs, ink PDF, teal IQ.
struct Wordmark: View {
    var size: CGFloat = 24
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.16) {
            Text("fs").foregroundColor(.fsRed)
            Text("PDF").foregroundColor(.primary)
            Text("IQ").foregroundColor(.fsTeal)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("fs PDF IQ")
    }
}

/// Liquid-glass style card.
struct GlassCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.25 : 0.85), Color.white.opacity(0.05)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.07), radius: 16, x: 0, y: 8)
    }
}

extension View {
    func glass(_ radius: CGFloat = 22) -> some View { modifier(GlassCard(radius: radius)) }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.05, green: 0.06, blue: 0.07) : Color(red: 0.965, green: 0.97, blue: 0.975))
            Circle().fill(Color.fsRed.opacity(scheme == .dark ? 0.22 : 0.14)).frame(width: 420, height: 420)
                .blur(radius: 110).offset(x: -170, y: -320)
            Circle().fill(Color.fsTeal.opacity(scheme == .dark ? 0.26 : 0.17)).frame(width: 460, height: 460)
                .blur(radius: 120).offset(x: 180, y: 160)
        }
        .ignoresSafeArea()
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = .fsRed
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .fsTeal
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(tint)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(tint.opacity(0.12), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.bold))
            .foregroundColor(.secondary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
