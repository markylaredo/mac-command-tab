import SwiftUI

struct WindowCardView: View {
    let window: WindowInfo
    let preview: WindowPreview?
    let isSelected: Bool
    let index: Int
    let preset: SwitcherPreset
    let theme: SwitcherTheme
    let selectionEffect: SwitcherSelectionEffect
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch preset {
            case .circle:
                tileCard
            case .tile:
                tileCard
            case .carousel:
                carouselCard
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.title), \(window.applicationName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var tileCard: some View {
        VStack(spacing: 7) {
            previewView(width: 190, height: 88, radius: 6)
                .overlay(alignment: .topLeading) {
                    indexBadge(accent: theme.accent)
                }

            HStack(spacing: 7) {
                appIcon(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(window.applicationName.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(8)
        .frame(width: 206, height: 132)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? theme.selectedCardFill : theme.cardFill)
        }
        .overlay {
            selectionOutline(cornerRadius: 9, lineWidth: 2.1)
        }
        .overlay {
            SelectionEffectOverlay(
                effect: selectionEffect,
                theme: theme,
                cornerRadius: 9,
                isSelected: isSelected
            )
        }
        .shadow(color: isSelected ? theme.accent.opacity(selectionGlowOpacity) : .clear, radius: selectionGlowRadius)
        .scaleEffect(isSelected ? selectedScale : 0.97)
        .offset(y: isSelected && selectionEffect != .none ? -2 : 0)
        .opacity(isSelected ? 1 : 0.72)
        .animation(selectionAnimation, value: isSelected)
    }

    private var carouselCard: some View {
        VStack(spacing: 8) {
            previewView(width: 226, height: 118, radius: 5)
                .overlay(alignment: .topLeading) {
                    indexBadge(accent: theme.accent)
                }

            HStack(spacing: 8) {
                appIcon(size: 25)
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(window.applicationName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(isSelected ? theme.accent : theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .padding(9)
        .frame(width: 246, height: 180)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? theme.selectedCardFill : theme.cardFill)
        }
        .overlay {
            selectionOutline(cornerRadius: 7, lineWidth: 2.2)
        }
        .overlay {
            SelectionEffectOverlay(
                effect: selectionEffect,
                theme: theme,
                cornerRadius: 7,
                isSelected: isSelected
            )
        }
        .shadow(color: isSelected ? theme.accent.opacity(selectionGlowOpacity) : .clear, radius: selectionGlowRadius)
        .scaleEffect(isSelected ? selectedScale : 0.975)
        .opacity(isSelected ? 1 : 0.72)
        .animation(selectionAnimation, value: isSelected)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.72)
    }

    private var selectedScale: CGFloat {
        switch selectionEffect {
        case .focusLift: theme == .modern ? 1.045 : 1.035
        case .neonSweep: 1.025
        case .emberBurn: 1.03
        case .none: 1
        }
    }

    private var selectionGlowOpacity: Double {
        switch selectionEffect {
        case .focusLift: theme == .classic ? 0.18 : 0.30
        case .neonSweep: 0.52
        case .emberBurn: 0.20
        case .none: 0
        }
    }

    private var selectionGlowRadius: CGFloat {
        selectionEffect == .neonSweep ? 22 : 15
    }

    @ViewBuilder
    private func selectionOutline(cornerRadius: CGFloat, lineWidth: CGFloat) -> some View {
        if isSelected {
            switch theme {
            case .game:
                TacticalSelectionCorners()
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square))
                    .padding(2)
            case .classic:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(theme.accent, lineWidth: lineWidth + 0.5)
                    .padding(1)
            case .modern:
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [theme.accent, theme.secondaryAccent, theme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: lineWidth
                    )
                    .padding(1)
            }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.primaryText.opacity(0.09), lineWidth: 1)
        }
    }

    private func indexBadge(accent: Color) -> some View {
        Text(String(format: "%02d", index + 1))
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundStyle(isSelected ? selectedBadgeText : theme.primaryText.opacity(0.74))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? accent : theme.cardFill.opacity(0.92))
            .padding(6)
    }

    @ViewBuilder
    private func previewView(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        ZStack {
            Color.primary.opacity(0.055)
            if let preview {
                Image(decorative: preview.image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                appIcon(size: 50)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        ApplicationIcon(window: window, size: size)
    }

    private var selectedBadgeText: Color {
        theme == .classic ? .white : .black
    }
}

struct CircleWindowNode: View {
    let window: WindowInfo
    let index: Int
    let isSelected: Bool
    let theme: SwitcherTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ApplicationIcon(window: window, size: 38)
            .padding(8)
            .background {
                Circle()
                    .fill(isSelected ? theme.selectedCardFill : theme.cardFill)
            }
            .overlay {
                Circle()
                    .stroke(isSelected ? theme.accent : theme.primaryText.opacity(0.18), lineWidth: isSelected ? 3 : 1)
            }
            .overlay(alignment: .bottomTrailing) {
                Text(String(index + 1))
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? selectedBadgeText : theme.primaryText.opacity(0.85))
                    .frame(minWidth: 17, minHeight: 17)
                    .background(isSelected ? theme.accent : theme.cardFill, in: Circle())
                    .offset(x: 3, y: 3)
            }
            .shadow(color: isSelected ? theme.accent.opacity(theme == .modern ? 0.68 : 0.48) : .black.opacity(0.30), radius: isSelected ? 18 : 5)
            .scaleEffect(isSelected ? 1.18 : 0.92)
            .animation(reduceMotion ? nil : .spring(response: 0.23, dampingFraction: 0.67), value: isSelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.title), \(window.applicationName)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectedBadgeText: Color {
        theme == .classic ? .white : .black
    }
}

struct CircleSelectionCard: View {
    let window: WindowInfo
    let preview: WindowPreview?
    let theme: SwitcherTheme
    let selectionEffect: SwitcherSelectionEffect

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                theme.cardFill
                if let preview {
                    Image(decorative: preview.image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    ApplicationIcon(window: window, size: 66)
                }
            }
            .frame(width: 268, height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.secondaryAccent.opacity(0.34), lineWidth: 1)
            }

            HStack(spacing: 9) {
                ApplicationIcon(window: window, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(window.applicationName.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "viewfinder")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(10)
        .frame(width: 290, height: 206)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.selectedCardFill)
        }
        .overlay {
            selectionOutline
        }
        .overlay {
            SelectionEffectOverlay(
                effect: selectionEffect,
                theme: theme,
                cornerRadius: 14,
                isSelected: true
            )
        }
        .shadow(
            color: selectionEffect == .none ? .clear : theme.accent.opacity(theme == .modern ? 0.42 : 0.22),
            radius: theme == .modern ? 28 : 22
        )
    }

    @ViewBuilder
    private var selectionOutline: some View {
        switch theme {
        case .game:
            TacticalSelectionCorners()
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .square))
                .padding(3)
        case .classic:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.accent, lineWidth: 3)
                .padding(1)
        case .modern:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [theme.accent, theme.secondaryAccent, theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.4
                )
                .padding(1)
        }
    }
}

struct SelectionEffectOverlay: View {
    let effect: SwitcherSelectionEffect
    let theme: SwitcherTheme
    let cornerRadius: CGFloat
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if isSelected {
            switch effect {
            case .focusLift:
                FocusLiftSelectionEffect(
                    color: theme.accent,
                    cornerRadius: cornerRadius,
                    reduceMotion: reduceMotion
                )
            case .neonSweep:
                NeonSweepSelectionEffect(
                    primary: theme.accent,
                    secondary: theme.secondaryAccent,
                    cornerRadius: cornerRadius,
                    reduceMotion: reduceMotion
                )
            case .emberBurn:
                EmberBurnSelectionEffect(cornerRadius: cornerRadius, reduceMotion: reduceMotion)
            case .none:
                EmptyView()
            }
        }
    }
}

private struct FocusLiftSelectionEffect: View {
    let color: Color
    let cornerRadius: CGFloat
    let reduceMotion: Bool
    @State private var expanded = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(color.opacity(0.72), lineWidth: 1.5)
            .scaleEffect(reduceMotion ? 1 : (expanded ? 1.075 : 0.96))
            .opacity(reduceMotion ? 0.52 : (expanded ? 0 : 0.75))
            .shadow(color: color.opacity(0.38), radius: 9)
            .padding(2)
            .onAppear {
                guard !reduceMotion else { return }
                expanded = true
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.42), value: expanded)
            .allowsHitTesting(false)
    }
}

private struct NeonSweepSelectionEffect: View {
    let primary: Color
    let secondary: Color
    let cornerRadius: CGFloat
    let reduceMotion: Bool
    @State private var rotating = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(primary.opacity(0.30), lineWidth: 1)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .trim(from: 0, to: 0.24)
                .stroke(
                    LinearGradient(
                        colors: [.clear, primary, secondary, .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(reduceMotion ? 28 : (rotating ? 360 : 0)))
                .shadow(color: primary.opacity(0.75), radius: 8)
        }
        .padding(1)
        .onAppear {
            guard !reduceMotion else { return }
            rotating = true
        }
        .animation(
            reduceMotion ? nil : .linear(duration: 1.05).repeatForever(autoreverses: false),
            value: rotating
        )
        .allowsHitTesting(false)
    }
}

private struct EmberBurnSelectionEffect: View {
    let cornerRadius: CGFloat
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
                let outline = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: bounds)
                context.stroke(outline, with: .color(Color(red: 1.0, green: 0.33, blue: 0.06).opacity(0.90)), lineWidth: 2)

                guard !reduceMotion else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let particleCount = 22

                for index in 0..<particleCount {
                    let seed = Double((index * 43 + 17) % 101) / 101.0
                    let speed = 0.62 + Double(index % 5) * 0.08
                    let progress = (time * speed + seed).truncatingRemainder(dividingBy: 1)
                    let horizontal = CGFloat(seed) * max(size.width - 18, 1) + 9
                    let drift = CGFloat(sin(time * 3.2 + Double(index))) * 5
                    let rise = CGFloat(progress) * min(size.height * 0.46, 72)
                    let diameter = CGFloat(2.2 + Double(index % 4) * 0.85) * (1 - CGFloat(progress) * 0.45)
                    let particleRect = CGRect(
                        x: horizontal + drift - diameter / 2,
                        y: size.height - 6 - rise,
                        width: diameter,
                        height: diameter * 1.45
                    )
                    var particleContext = context
                    particleContext.opacity = sin(progress * .pi) * 0.92
                    let color = index.isMultiple(of: 3)
                        ? Color(red: 1.0, green: 0.84, blue: 0.26)
                        : Color(red: 1.0, green: 0.22, blue: 0.035)
                    particleContext.fill(Path(ellipseIn: particleRect), with: .color(color))
                }
            }
        }
        .compositingGroup()
        .shadow(color: Color.orange.opacity(0.62), radius: reduceMotion ? 4 : 10)
        .allowsHitTesting(false)
    }
}

struct ApplicationIcon: View {
    let window: WindowInfo
    let size: CGFloat

    var body: some View {
        Group {
            if let icon = window.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct TacticalSelectionCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.14
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}
