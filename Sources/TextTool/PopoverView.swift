import ServiceManagement
import SwiftUI
import TextToolCore

struct PopoverView: View {
    @ObservedObject var model: ClipboardModel
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Controls stay at the top so they don't move when the preview's height
            // changes between items; the preview grows downward, away from the menu bar.
            header
            if let release = updater.availableUpdate {
                updateBanner(release)
                    .transition(appear)
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
        .overlay {
            if isDropTargeted { dropOverlay.transition(appear) }
        }
        // Occasional events get a short ease-out; exits are quicker than entrances.
        .animation(.easeOut(duration: isDropTargeted ? 0.16 : 0.12), value: isDropTargeted)
        .animation(.easeOut(duration: 0.2), value: updater.availableUpdate != nil)
    }

    /// Fade with a slight scale (never from zero); just a fade with Reduce Motion on.
    private var appear: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
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
            Spacer()
            settingsMenu
        }
        .frame(height: 22)
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
        VStack(alignment: .leading, spacing: 0) {
            if model.canEdit || model.isRecognizing || model.errorMessage != nil {
                previewMeta
            }

            if case .image(let image) = model.source {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.08)))
                    .padding(.horizontal, SelectableTextView.inset)
                    .padding(.bottom, 4)
            }

            if model.isRecognizing {
                placeholder(icon: nil, title: "Recognizing text…", hint: nil, showsProgress: true)
            } else if let error = model.errorMessage {
                placeholder(icon: "exclamationmark.triangle", title: error, hint: nil)
            } else if model.canEdit {
                // An invisible Text sizes the box (70–180pt); the native text view on top
                // handles editing, selection, undo, copy/paste and scrolling.
                Text(model.current.isEmpty ? " " : model.current)
                    .font(.system(size: SelectableTextView.fontSize))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SelectableTextView.inset)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .frame(minHeight: 64, maxHeight: 180, alignment: .top)
                    .overlay(SelectableTextView(text: model.current) { model.edit($0) })
                    .help("Click to edit. Changes are copied to the clipboard as you type.")
            } else if model.source == .unsupported {
                placeholder(icon: "questionmark.square.dashed",
                            title: "The clipboard has no text or image",
                            hint: "Copy something else, or drop it here")
            } else {
                placeholder(icon: "square.and.arrow.down",
                            title: "Copy text or an image",
                            hint: "Or drop it here  ·  ⌘V to paste")
            }
        }
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
    }

    /// What the preview holds (left) and its size, or a "Copied" confirmation (right).
    private var previewMeta: some View {
        HStack(spacing: 5) {
            if case .image = model.source {
                Image(systemName: "text.viewfinder")
                Text("From image")
            } else {
                Image(systemName: "text.alignleft")
                Text("Text")
            }
            Spacer(minLength: 8)
            if model.copiedFlash {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if model.hasText {
                Text(stats)
                    .monospacedDigit()
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, SelectableTextView.inset)
        .frame(height: 26)
        .animation(.easeOut(duration: 0.15), value: model.copiedFlash)
    }

    private func placeholder(icon: String?, title: String, hint: String?, showsProgress: Bool = false) -> some View {
        VStack(spacing: 6) {
            if showsProgress {
                ProgressView().controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 88)
        .padding(10)
    }

    // MARK: - Case buttons

    private var caseButtons: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(TextCase.allCases.enumerated()), id: \.element) { index, textCase in
                Button(textCase.label) { model.apply(textCase) }
                    .buttonStyle(CaseButtonStyle(isSelected: model.selectedCase == textCase))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(textCase.label)  ⌘\(index + 1)")
            }
        }
        .disabled(!model.hasText || model.isRecognizing)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Button {
                model.showOlder()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(IconButtonStyle())
            .disabled(!model.canGoOlder)
            .keyboardShortcut("[", modifiers: .command)
            .help("Previous copied item  ⌘[")

            Text(historyPosition)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 28)

            Button {
                model.showNewer()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(IconButtonStyle())
            .disabled(!model.canGoNewer)
            .keyboardShortcut("]", modifiers: .command)
            .help("Next copied item  ⌘]")

            Spacer()

            Button {
                model.restoreOriginal()
            } label: {
                Label("Original", systemImage: "arrow.uturn.backward")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(model.selectedCase == nil)
            .keyboardShortcut("0", modifiers: .command)
            .help("Restore the original text  ⌘0")
        }
        .frame(height: 22)
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

/// Case buttons: quiet fill, hover tint, instant press feedback, accent fill when selected.
private struct CaseButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        CaseButtonBody(configuration: configuration, isSelected: isSelected)
    }

    private struct CaseButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let isSelected: Bool

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(fill, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }

        private var fill: Color {
            if isSelected {
                return configuration.isPressed ? Color.accentColor.opacity(0.85) : Color.accentColor
            }
            guard isEnabled else { return Color.primary.opacity(0.05) }
            if configuration.isPressed { return Color.primary.opacity(0.16) }
            return Color.primary.opacity(isHovering ? 0.1 : 0.06)
        }
    }
}

/// Small borderless controls (history arrows, Original) with a real hit area and hover state.
private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.75) : Color.primary.opacity(0.25))
                .frame(minWidth: 22, minHeight: 22)
                .background(fill, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }

        private var fill: Color {
            guard isEnabled else { return .clear }
            if configuration.isPressed { return Color.primary.opacity(0.14) }
            return isHovering ? Color.primary.opacity(0.08) : .clear
        }
    }
}
