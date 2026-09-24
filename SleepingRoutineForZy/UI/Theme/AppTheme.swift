import SwiftUI

enum AppTheme {
    static let backgroundTop = Color(red: 0.06, green: 0.08, blue: 0.16)
    static let backgroundBottom = Color(red: 0.10, green: 0.10, blue: 0.18)
    static let cardBackground = Color.white.opacity(0.08)
    static let accent = Color(red: 0.55, green: 0.48, blue: 0.90)
    static let accentSoft = Color(red: 0.40, green: 0.55, blue: 0.92)
    static let primaryText = Color.white.opacity(0.95)
    static let secondaryText = Color.white.opacity(0.65)
    static let tertiaryText = Color.white.opacity(0.45)
    static let destructive = Color(red: 0.90, green: 0.40, blue: 0.45)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    enum Typography {
        static let hero = Font.system(size: 34, weight: .semibold, design: .rounded)
        static let title = Font.system(size: 28, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 17, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 14, weight: .regular, design: .rounded)
    }

    static let minTouchTarget: CGFloat = 44
    static let cardCornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 20
}

struct NightSkyBackground: View {
    var showMoonAndStars: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient.ignoresSafeArea()

            if showMoonAndStars {
                moon
                stars
            }

            if !reduceMotion {
                Circle()
                    .fill(AppTheme.accent.opacity(0.12))
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
                    .offset(x: 110, y: -180)
                Circle()
                    .fill(AppTheme.accentSoft.opacity(0.10))
                    .frame(width: 180, height: 180)
                    .blur(radius: 36)
                    .offset(x: -120, y: 220)
            }
        }
        .accessibilityHidden(true)
    }

    private var moon: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(0.85), Color.white.opacity(0.15)],
                    center: .topLeading,
                    startRadius: 4,
                    endRadius: 40
                )
            )
            .frame(width: 56, height: 56)
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(AppTheme.backgroundTop.opacity(0.55))
                    .frame(width: 40, height: 40)
                    .offset(x: 10, y: -6)
            }
            .offset(x: 120, y: -260)
            .opacity(reduceMotion ? 0.7 : 1)
    }

    private var stars: some View {
        Canvas { context, size in
            let points: [CGPoint] = [
                CGPoint(x: size.width * 0.12, y: size.height * 0.18),
                CGPoint(x: size.width * 0.28, y: size.height * 0.12),
                CGPoint(x: size.width * 0.45, y: size.height * 0.22),
                CGPoint(x: size.width * 0.62, y: size.height * 0.10),
                CGPoint(x: size.width * 0.78, y: size.height * 0.20),
                CGPoint(x: size.width * 0.18, y: size.height * 0.32),
                CGPoint(x: size.width * 0.88, y: size.height * 0.34)
            ]
            for point in points {
                let rect = CGRect(x: point.x, y: point.y, width: 2.5, height: 2.5)
                context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55)))
            }
        }
        .allowsHitTesting(false)
    }
}
