import SwiftUI
import UIKit

final class ComposerTextView: UITextView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

func chatComposerUIFont(_ size: CGFloat = 17) -> UIFont {
    let scaled = max(9, (size * fontScale * CareMode.scale).rounded())
    if let name = pfName(.regular), let font = UIFont(name: name, size: scaled) {
        return font
    }
    return .systemFont(ofSize: scaled)
}

@MainActor
final class ChatComposerBridge: ObservableObject {
    fileprivate weak var textView: UITextView?
    fileprivate var onTextMutation: ((String) -> Void)?
    private var lastSelection = NSRange(location: 0, length: 0)

    fileprivate func attach(_ view: UITextView,
                            onTextMutation: ((String) -> Void)? = nil) {
        textView = view
        if let onTextMutation {
            self.onTextMutation = onTextMutation
        }
        rememberSelection(in: view)
    }

    fileprivate func rememberSelection(in view: UITextView) {
        lastSelection = view.selectedRange
    }

    func insert(_ text: String) {
        replaceSelection(with: text)
    }

    func deleteBackward() {
        guard let view = textView else { return }
        let current = view.text ?? ""
        let selected = currentSelection(in: view, textCount: (current as NSString).length)

        if selected.length > 0 {
            replaceSelection(with: "")
            return
        }

        guard selected.location > 0,
              let cursor = Range(NSRange(location: selected.location, length: 0), in: current),
              let from = current.index(cursor.lowerBound, offsetBy: -1, limitedBy: current.startIndex)
        else { return }

        let range = from..<cursor.lowerBound
        let cursorUTF16 = current.utf16.distance(from: current.startIndex, to: from)
        let next = current.replacingCharacters(in: range, with: "")
        apply(next, cursorUTF16: cursorUTF16, to: view)
    }

    private func replaceSelection(with text: String) {
        guard let view = textView else { return }
        let current = view.text ?? ""
        let selected = currentSelection(in: view, textCount: (current as NSString).length)
        guard let range = Range(selected, in: current) else { return }

        let insertion = text as NSString
        let next = current.replacingCharacters(in: range, with: text)
        let cursor = selected.location + insertion.length
        apply(next, cursorUTF16: cursor, to: view)
    }

    private func currentSelection(in view: UITextView, textCount: Int) -> NSRange {
        rememberSelection(in: view)
        let upper = max(0, textCount)
        let location = min(max(0, lastSelection.location), upper)
        let length = min(max(0, lastSelection.length), upper - location)
        return NSRange(location: location, length: length)
    }

    private func apply(_ text: String, cursorUTF16: Int, to view: UITextView) {
        view.text = text

        let upper = (text as NSString).length
        let safe = min(max(0, cursorUTF16), upper)
        let selection = NSRange(location: safe, length: 0)
        view.selectedRange = selection
        lastSelection = selection
        view.scrollRangeToVisible(selection)
        onTextMutation?(text)
    }
}

struct ChatComposerTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let bridge: ChatComposerBridge
    let font: UIFont
    let tintColor: UIColor
    let textColor: UIColor
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onBeginEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ComposerTextView {
        let view = ComposerTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceVertical = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.font = font
        view.tintColor = tintColor
        view.textColor = textColor
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bridge.attach(view) { value in
            context.coordinator.parent.text = value
        }
        view.onLayout = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.reportHeight(view)
        }
        return view
    }

    func updateUIView(_ view: ComposerTextView, context: Context) {
        context.coordinator.parent = self
        view.onLayout = { [weak view, weak coordinator = context.coordinator] in
            guard let view, let coordinator else { return }
            coordinator.reportHeight(view)
        }
        bridge.attach(view) { value in
            context.coordinator.parent.text = value
        }
        view.font = font
        view.tintColor = tintColor
        view.textColor = textColor

        if view.text != text {
            let selected = view.selectedRange
            view.text = text
            let length = (view.text as NSString).length
            let location = min(selected.location, length)
            let rangeLength = min(selected.length, length - location)
            view.selectedRange = NSRange(location: location, length: rangeLength)
            bridge.rememberSelection(in: view)
        }

        if focused && !view.isFirstResponder {
            DispatchQueue.main.async {
                guard self.focused, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
            }
        } else if !focused && view.isFirstResponder {
            DispatchQueue.main.async {
                guard !self.focused, view.isFirstResponder else { return }
                view.resignFirstResponder()
            }
        }

        context.coordinator.reportHeight(view)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChatComposerTextField
        private var lastHeight: CGFloat = 0

        init(parent: ChatComposerTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ view: UITextView) {
            parent.text = view.text ?? ""
            parent.bridge.rememberSelection(in: view)
            reportHeight(view)
        }

        func textViewDidChange(_ textView: UITextView) {
            textChanged(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
            parent.bridge.rememberSelection(in: textView)
            parent.onBeginEditing()
            reportHeight(textView)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.bridge.rememberSelection(in: textView)
        }

        func reportHeight(_ view: UITextView, force: Bool = false) {
            let width = max(1, view.bounds.width)
            guard width > 20 else { return }
            view.layoutManager.ensureLayout(for: view.textContainer)
            let fitting = ceil(view.layoutManager.usedRect(for: view.textContainer).height)
            let next = min(parent.maxHeight, max(parent.minHeight, ceil(fitting)))
            guard force || abs(next - lastHeight) > 0.5 else { return }
            lastHeight = next
            DispatchQueue.main.async {
                self.parent.onHeightChange(next)
            }
        }
    }
}
