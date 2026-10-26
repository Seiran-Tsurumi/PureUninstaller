import SwiftUI
import AppKit

/// Cached app icons. `NSWorkspace` icon loading is main-thread-only.
@MainActor
final class AppIconCache {
    static let shared = AppIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        let key = url.path
        if let cached = cache[key] { return cached }
        let image = NSWorkspace.shared.icon(forFile: key)
        image.size = NSSize(width: 32, height: 32)
        cache[key] = image
        return image
    }
}

struct AppIconView: View {
    let url: URL
    var size: CGFloat = 22
    // SwiftUI's `@State` attribute is a macro in newer SDKs. The command-line
    // toolchain used for this project does not ship the SwiftUIMacros plugin,
    // so the backing `State` property wrapper is declared explicitly. This is
    // the same storage the macro would synthesize.
    private var _image = State<NSImage?>(wrappedValue: nil)
    private var image: NSImage? { _image.wrappedValue }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            _image.wrappedValue = AppIconCache.shared.icon(for: url)
        }
    }
}

struct Badge: View {
    let text: String
    var systemImage: String?
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.10), in: Capsule())
    }
}

struct TriStateCheckbox: View {
    let state: UninstallSession.CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(state == .off || state == .locked ? Color.secondary : Color.accentColor)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .disabled(state == .locked)
        .help(state == .locked ? "受系统保护，不能删除" : "选择 / 取消选择")
    }
}

struct SearchBox: View {
    @Binding var text: String
    var placeholder: String = "搜索应用、Bundle ID 或路径"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .frame(width: 260)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DividerLine: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 0.5)
    }
}

extension Color {
    static var riskLow: Color { .green }
    static var riskMedium: Color { .orange }
    static var riskHigh: Color { .red }
}

extension ResidueRisk {
    var color: Color {
        switch self {
        case .low: return .riskLow
        case .medium: return .riskMedium
        case .high: return .riskHigh
        }
    }
}

extension OrphanConfidence {
    var color: Color {
        switch self {
        case .high: return .green
        case .medium: return .orange
        case .low: return .secondary
        }
    }
}
