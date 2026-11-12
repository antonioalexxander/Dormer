import AppKit
import DormerCore
import SwiftUI

// MARK: - Surfaces

/// Liquid Glass on macOS 26 and later, a translucent material before that.
struct SurfaceModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.regularMaterial, in: shape)
            }
        #else
            content.background(.regularMaterial, in: shape)
        #endif
    }
}

extension View {
    func surface<S: Shape>(in shape: S) -> some View {
        modifier(SurfaceModifier(shape: shape))
    }

    func surface(cornerRadius: CGFloat = 12) -> some View {
        modifier(SurfaceModifier(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }
}

// MARK: - Program icon

/// Placeholder icon until icons are extracted from `.exe` files (Phase 3):
/// a monogram on a color derived from the program's name.
/// A program's icon read from its executable, or a colored monogram while loading or when it has none.
struct ProgramIconView: View {
    let name: String
    var size: CGFloat = 48
    var program: Program?
    var bottleID: UUID?

    @Environment(AppModel.self) private var model
    @State private var image: NSImage?

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .teal, .green, .cyan, .mint]

    private var color: Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[hash % Self.palette.count]
    }

    private var monogram: String {
        name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(color.gradient)
                    .overlay {
                        Text(monogram)
                            .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: program?.pathKey) {
            guard let program, let bottleID else { return }
            image = await model.icon(for: program, in: bottleID)
        }
    }
}

// MARK: - Badges

struct BadgeView: View {
    let text: LocalizedStringKey
    var tint: Color = .orange

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(tint)
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Small pulsing dot that marks running processes.
struct RunningIndicator: View {
    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 7, height: 7)
            .accessibilityLabel(Text("En ejecución"))
    }
}

// MARK: - Preview notice

/// Persistent notice shown while the app runs on sample data.
struct PreviewNotice: View {
    var body: some View {
        Label {
            Text("Vista previa con datos de ejemplo · Wine aún no está conectado")
        } icon: {
            Image(systemName: "eye")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Formatting

enum Formatters {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static let time: Date.FormatStyle = .dateTime.hour().minute().second()
}
