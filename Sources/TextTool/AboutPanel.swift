import AppKit
import SwiftUI

/// A compact About window: app identity plus a short, scannable guide. Sized to fit without scrolling.
@MainActor
enum AboutPanel {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: AboutView())
            hosting.sizingOptions = .preferredContentSize
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct AboutView: View {
    private struct Feature: Identifiable {
        let icon: String
        let title: String
        let detail: String
        let keys: String?
        var id: String { title }
    }

    private let features = [
        Feature(icon: "textformat", title: "Change case",
                detail: "Copy text, click the Text Tool icon in the menu bar, and pick a case. The result is copied instantly.",
                keys: "⌘1–⌘6  ·  ⌘0 original"),
        Feature(icon: "text.viewfinder", title: "Text from images",
                detail: "Copy a screenshot or image, click the Text Tool icon in the menu bar, and paste its text.",
                keys: nil),
        Feature(icon: "clock.arrow.circlepath", title: "History",
                detail: "Step through your last 10 copies. Cleared when you quit.",
                keys: "⌘[  ⌘]"),
        Feature(icon: "lock.shield", title: "Private",
                detail: "Runs entirely on your Mac. Nothing is uploaded.",
                keys: nil),
    ]

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Text Tool")
                    .font(.system(size: 17, weight: .semibold))
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Clipboard text, made smart.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(features) { feature in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(feature.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let keys = feature.keys {
                                Text(keys)
                                    .font(.system(size: 11, design: .rounded))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
        .frame(width: 340)
    }
}
