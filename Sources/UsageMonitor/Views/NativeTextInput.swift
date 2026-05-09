import AppKit
import SwiftUI

struct NativeTextInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var autoFocus = false

    func makeCoordinator() -> NativeTextInputCoordinator {
        NativeTextInputCoordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField: NSTextField = secure
            ? NSSecureTextField(frame: .zero)
            : NSTextField(frame: .zero)
        configure(textField, coordinator: context.coordinator)
        textField.stringValue = text
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        configure(textField, coordinator: context.coordinator)
        if textField.stringValue != text {
            textField.stringValue = text
        }
        if autoFocus {
            context.coordinator.requestInitialFocus(on: textField)
        }
    }

    private func configure(_ textField: NSTextField, coordinator: NativeTextInputCoordinator) {
        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.focusRingType = .default
        textField.allowsEditingTextAttributes = false
        textField.delegate = coordinator
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
}

final class NativeTextInputCoordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>
    private var didRequestInitialFocus = false

    init(text: Binding<String>) {
        self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
        syncText(from: notification)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        syncText(from: notification)
    }

    func requestInitialFocus(on textField: NSTextField) {
        guard !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        DispatchQueue.main.async { [weak textField] in
            textField?.selectText(nil)
        }
    }

    private func syncText(from notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }
        text.wrappedValue = textField.stringValue
    }
}
