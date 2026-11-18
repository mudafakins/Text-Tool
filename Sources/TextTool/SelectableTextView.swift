import AppKit
import SwiftUI

/// An editable, scrollable plain-text view backed by NSTextView, so typing, selection,
/// undo, ⌘A / ⌘C / ⌘X / ⌘V and the right-click menu behave like any native Mac text.
struct SelectableTextView: NSViewRepresentable {
    static let fontSize: CGFloat = 13
    static let inset: CGFloat = 10

    let text: String
    var onEdit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEdit: onEdit) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = true
            textView.isSelectable = true
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: Self.fontSize)
            textView.textColor = .labelColor
            textView.insertionPointColor = .controlAccentColor
            textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
            textView.textContainer?.lineFragmentPadding = 0
            // Keep text exactly as typed: no smart quotes, dashes, autocorrect or spell-check marks.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.string = text
            textView.delegate = context.coordinator
            // Drops go to the popover (as a new item) rather than into this text.
            textView.unregisterDraggedTypes()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onEdit = onEdit
        // Only replace the text when it changed from outside (new item, case button),
        // never while it matches what the user just typed — that would reset the cursor.
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onEdit: (String) -> Void

        init(onEdit: @escaping (String) -> Void) {
            self.onEdit = onEdit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onEdit(textView.string)
        }
    }
}
