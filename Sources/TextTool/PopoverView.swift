import ServiceManagement
import SwiftUI
import TextToolCore

struct PopoverView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isDropTargeted = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls stay at the top so they don't move when the preview's height
            // changes between items; the preview grows downward, away from the menu bar.
            header
            if let release = updater.availableUpdate {
                updateBanner(release)
            }
            caseButtons
            footer
            preview
        }
        .padding(12)
        .frame(width: 360)
        .onDrop(of: [.fileURL, .image, .text], isTargeted: $isDropTargeted) { providers in
            model.ingest(providers: providers)
        }
        .overlay { if isDropTargeted { dropOverlay } }
    }

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            VStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Drop an image or text")
                    .font(.system(size: 13, weight: .semibold))
                Text("Images are converted to text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .allowsHitTesting(false)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "textformat")
                .foregroundStyle(.secondary)
            Text("Text Tool")
                .font(.headline)
            sourceBadge
            Spacer()
            settingsMenu
        }
        // Fixed height: badges with different icons (or no badge) must not resize the row.
        .frame(height: 22)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch model.source {
        case .text:
            Badge(text: "Text", systemImage: "doc.plaintext")
        case .image:
            Badge(text: "Image · OCR", systemImage: "text.viewfinder")
        case .empty, .unsupported:
            EmptyView()
        }
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("Replace copied images with text", isOn: $model.autoReplaceImages)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            Divider()
            Text("Text Tool \(updater.currentVersion)")
            Button("Check for Updates…") {
                Task { await updater.check(userInitiated: true) }
            }
            .disabled(updater.state != .idle)
            Toggle("Automatically Check for Updates", isOn: $updater.automaticallyChecks)
            Divider()
            Button {
                AboutPanel.show()
            } label: {
                Label("About Text Tool", systemImage: "info.circle")
            }
            Button("Quit Text Tool") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }

    private func updateBanner(_ release: Updater.Release) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Version \(release.version) is available")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if updater.state == .installing {
                ProgressView().controlSize(.small)
                Text("Updating…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Update") { Task { await updater.install(release) } }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Preview

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .image(let image) = model.source {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Group {
                if model.isRecognizing {
                    placeholder {
                        ProgressView().controlSize(.small)
                        Text("Recognizing text…")
                    }
                } else if let error = model.errorMessage {
                    placeholder {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                    }
                } else if model.hasText {
                    // An invisible Text sizes the box (70–180pt); the native text view on top
                    // handles selection, ⌘A / ⌘C, right-click Copy and scrolling.
                    Text(model.current)
                        .font(.system(size: SelectableTextView.fontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SelectableTextView.inset)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .frame(minHeight: 70, maxHeight: 180, alignment: .top)
                        .overlay(SelectableTextView(text: model.current))
                        .help("Select text and press ⌘C to copy part of it")
                } else {
                    placeholder {
                        Image(systemName: "square.and.arrow.down")
                        Text(model.source == .unsupported
                             ? "The clipboard doesn't contain text or an image."
                             : "Copy text or an image, or drop one here.")
                        Text("You can also paste with ⌘V or drop onto the menu bar icon.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 6) { content() }
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 70)
            .padding(10)
    }

    // MARK: - Case buttons

    private var caseButtons: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(TextCase.allCases.enumerated()), id: \.element) { index, textCase in
                CaseButton(
                    title: textCase.label,
                    isSelected: model.selectedCase == textCase
                ) {
                    model.apply(textCase)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(textCase.label)  ⌘\(index + 1)")
            }
        }
        .disabled(!model.hasText || model.isRecognizing)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            historyArrows

            Button {
                model.restoreOriginal()
            } label: {
                Label("Original", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(model.selectedCase == nil)
            .keyboardShortcut("0", modifiers: .command)
            .help("Restore the original text  ⌘0")

            Spacer()

            if model.copiedFlash {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if model.hasText {
                Text(stats)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .animation(.easeInOut(duration: 0.15), value: model.copiedFlash)
    }

    private var historyArrows: some View {
        HStack(spacing: 2) {
            Button {
                model.showOlder()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoOlder)
            .keyboardShortcut("[", modifiers: .command)
            .help("Previous copied item  ⌘[")

            Text(historyPosition)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 26)

            Button {
                model.showNewer()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoNewer)
            .keyboardShortcut("]", modifiers: .command)
            .help("Next copied item  ⌘]")
        }
        .buttonStyle(.borderless)
        .fontWeight(.semibold)
    }

    /// "1/4" where 1 is the newest item; "–/4" while showing something not kept in history.
    private var historyPosition: String {
        guard !model.history.isEmpty else { return "–" }
        let position = model.historyIndex.map { "\($0 + 1)" } ?? "–"
        return "\(position)/\(model.history.count)"
    }

    private var stats: String {
        let chars = model.current.count
        let words = CaseConverter.wordCount(model.current)
        return "\(words) word\(words == 1 ? "" : "s") · \(chars) char\(chars == 1 ? "" : "s")"
    }
}

// MARK: - Components

private struct CaseButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(background, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(isHovering && isEnabled ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
    }
}

private struct Badge: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .frame(width: 12, height: 12)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: 18)
        .background(.quaternary, in: Capsule())
    }
}
