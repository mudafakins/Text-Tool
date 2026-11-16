import AppKit
import SwiftUI

/// A read-only, selectable, scrollable text view backed by NSTextView, so selection,
/// ⌘A, ⌘C and the right-click Copy menu behave like any native Mac text.
struct SelectableTextView: NSViewRepresentable {
    static let fontSize: CGFloat = 13
    static let inset: CGFloat = 10

    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: Self.fontSize)
            textView.textColor = .labelColor
            textView.textContainerInset = NSSize(width: Self.inset, height: Self.inset)
            textView.textContainer?.lineFragmentPadding = 0
            textView.string = text
            // Let drops fall through to the popover instead of this read-only view.
            textView.unregisterDraggedTypes()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollToBeginningOfDocument(nil)
    }
}
