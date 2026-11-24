import AppKit
import KanbanCore
import SwiftUI

/// A wrapping, auto-growing text field with exact control over Return,
/// Shift+Return, Esc, losing focus, the 200-character cap and multi-line paste.
struct ComposerField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusRequest: Int
    var onSubmit: (_ openEditor: Bool) -> Void
    var onCancel: () -> Void
    var onFocusLost: () -> Void
    var onMultilinePaste: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ComposerTextField {
        let field = ComposerTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .semibold)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        field.usesSingleLineMode = false
        field.maximumNumberOfLines = 0
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("New task title")
        field.onPasteLines = { [weak coordinator = context.coordinator] lines in
            coordinator?.parent.onMultilinePaste(lines)
        }
        return field
    }

    func updateNSView(_ field: ComposerTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            field.invalidateIntrinsicContentSize()
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            DispatchQueue.main.async {
                guard let window = field.window, field.currentEditor() == nil else { return }
                window.makeFirstResponder(field)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerTextField, context: Context) -> CGSize? {
        let width = proposal.width ?? 220
        let measured = nsView.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(measured?.height ?? 17), 17))
    }

    static func dismantleNSView(_ field: ComposerTextField, coordinator: Coordinator) {
        coordinator.isDismantled = true
    }

    /// Splits pasted text into task titles: one per non-empty line, bullets stripped.
    static func lines(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { line -> String in
                var trimmed = line.trimmingCharacters(in: .whitespaces)
                for bullet in ["- [ ] ", "- [x] ", "• ", "- ", "* ", "– "] where trimmed.hasPrefix(bullet) {
                    trimmed = String(trimmed.dropFirst(bullet.count))
                    break
                }
                return String(trimmed.trimmingCharacters(in: .whitespaces).prefix(TaskCard.maxTitleLength))
            }
            .filter { !$0.isEmpty }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ComposerField
        var lastFocusRequest = Int.min
        var isDismantled = false

        init(_ parent: ComposerField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            // Typing undo would fight the board's ⌘Z (undo the last add).
            (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.allowsUndo = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            var value = field.stringValue
            if value.contains(where: \.isNewline) {
                // A paste that slipped past ⌘V (e.g. Edit ▸ Paste).
                let lines = ComposerField.lines(from: value)
                if lines.count > 1 {
                    field.stringValue = parent.text
                    parent.onMultilinePaste(lines)
                    return
                }
                value = lines.first ?? ""
                field.stringValue = value
            }
            if value.count > TaskCard.maxTitleLength {
                value = String(value.prefix(TaskCard.maxTitleLength))
                field.stringValue = value
            }
            parent.text = value
            field.invalidateIntrinsicContentSize()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            (notification.userInfo?["NSFieldEditor"] as? NSTextView)?.allowsUndo = true
            parent.onFocusLost()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                parent.onSubmit(shift)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

final class ComposerTextField: NSTextField {
    var onPasteLines: (([String]) -> Void)?

    /// Intercepts ⌘V when the clipboard holds several lines, so the composer
    /// can offer "Create N tasks?" instead of mashing them into one title.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "v", currentEditor() != nil,
           let string = NSPasteboard.general.string(forType: .string) {
            let lines = ComposerField.lines(from: string)
            if lines.count > 1 {
                onPasteLines?(lines)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
