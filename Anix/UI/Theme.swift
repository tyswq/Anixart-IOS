import SwiftUI

enum Theme {
    static let accent = Color(red: 0.94, green: 0.31, blue: 0.36)
}

// MARK: - Liquid Glass

@available(iOS 26.0, *)
private func makeGlass(interactive: Bool, tint: Color?) -> Glass {
    var g = Glass.regular
    if let tint { g = g.tint(tint) }
    if interactive { g = g.interactive() }
    return g
}

private struct ForceGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Плеер и подписи на постерах всегда стеклянные, даже в OLED-теме.
    var forceGlass: Bool {
        get { self[ForceGlassKey.self] }
        set { self[ForceGlassKey.self] = newValue }
    }
}

private struct GlassBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.forceGlass) private var forceGlass
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if settings.theme == .oled && !forceGlass {
            // OLED: чёрная плашка с тонкой обводкой, без серого стекла — чёрные пиксели не светятся
            content
                .background {
                    ZStack {
                        shape.fill(Color.black)
                        if let tint { shape.fill(tint.opacity(0.85)) }
                    }
                }
                .overlay { shape.stroke(Color.white.opacity(tint == nil ? 0.16 : 0), lineWidth: 0.6) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(makeGlass(interactive: interactive, tint: tint), in: shape)
        } else {
            content
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        if let tint { shape.fill(tint.opacity(0.85)) }
                    }
                }
                .overlay { shape.stroke(Color.primary.opacity(0.14), lineWidth: 0.5) }
        }
    }
}

extension View {
    /// Liquid Glass на iOS 26+, на более старых системах — матовый материал; в OLED-теме — чёрная плашка.
    func glassBackground<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GlassBackgroundModifier(shape: shape, interactive: interactive, tint: tint))
    }

    func glassCard(radius: CGFloat = 24, interactive: Bool = false, tint: Color? = nil) -> some View {
        glassBackground(RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive, tint: tint)
    }
}

/// Группа стеклянных элементов: на iOS 26 они «сливаются» друг с другом, как в системных панелях.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

// MARK: - Фон

/// Тёмный фон с размытым постером: цвет страницы подхватывает картинку.
struct AmbientBackground: View {
    @Environment(AppSettings.self) private var settings
    var image: String?

    var body: some View {
        let theme = settings.theme
        let glows = theme.glows
        if theme == .oled {
            // полностью чёрный фон: ни подсветки, ни размытого постера
            Color.black.ignoresSafeArea()
        } else {
        ZStack {
            theme.base
            RadialGradient(
                colors: [glows.0, .clear],
                center: .topTrailing, startRadius: 0, endRadius: 520
            )
            RadialGradient(
                colors: [glows.1, .clear],
                center: .bottomLeading, startRadius: 0, endRadius: 560
            )
            if let image, !image.isEmpty {
                Color.clear
                    .overlay { RemoteImage(url: image).blur(radius: 70).opacity(theme == .light ? 0.35 : 0.5) }
                    .clipped()
                LinearGradient(
                    colors: [.clear, theme.base.opacity(0.85), theme.base],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        }
    }
}
