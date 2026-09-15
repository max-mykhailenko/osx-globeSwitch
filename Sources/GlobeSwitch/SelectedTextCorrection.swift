import AppKit
@preconcurrency import ApplicationServices
import Carbon
import GlobeSwitchCore

struct SelectedTextTarget {
    let application: NSRunningApplication
    let element: AXUIElement
    let text: String?
    let range: CFRange?
    let markerRange: CFTypeRef?
}

/// Reads selection only on an explicit Globe/menu action. Never buffers typing.
@MainActor
final class SelectedTextCorrection {
    private(set) var isBusy = false
    private var converter: LayoutCorrection?
    var onError: ((String) -> Void)?

    var hasPermission: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func captureSelection(in application: NSRunningApplication? = nil) -> SelectedTextTarget? {
        guard hasPermission, !IsSecureEventInputEnabled(),
              let application = application ?? NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.08)
        guard let raw = attribute(appElement, kAXFocusedUIElementAttribute),
              CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeDowncast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.08)
        if attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
        let range = selectedRange(element)
        // Return early on the common no-selection path, before reading text.
        if let range, range.length == 0 { return nil }
        var selectedText = attribute(element, kAXSelectedTextAttribute) as? String
        let marker = attribute(element, "AXSelectedTextMarkerRange")
        if selectedText == nil, let marker {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, "AXStringForTextMarkerRange" as CFString, marker, &result) == .success {
                selectedText = result as? String
            }
        }
        guard (range?.length ?? 0) > 0 || !(selectedText ?? "").isEmpty else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String
        // Read-only page selections must not become a paste into another field.
        var writable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &writable)
        var writableSelection = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writableSelection)
        let editable = attribute(element, "AXEditable") as? Bool == true
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") || writable.boolValue || writableSelection.boolValue || editable else { return nil }
        return SelectedTextTarget(application: application, element: element, text: selectedText,
                                  range: range, markerRange: marker)
    }

    func replace(_ selection: SelectedTextTarget, target: CorrectionLanguage,
                 then switchSource: @escaping () throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task { @MainActor in
            defer { isBusy = false }
            do {
                guard hasPermission else { throw failure("Enable Accessibility for GlobeSwitch to correct selected text.") }
                if converter == nil { converter = try LayoutCorrection() }
                // Menu tracking and physical Fn/modifier releases must finish before
                // posting Command-C/V. Never activate a different app behind the user.
                for _ in 0..<100 {
                    let flags = CGEventSource.flagsState(.combinedSessionState)
                    if flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty { break }
                    try await Task.sleep(for: .milliseconds(20))
                }
                guard CGEventSource.flagsState(.combinedSessionState)
                    .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else {
                    throw failure("Release the Globe key and modifiers, then try again.")
                }
                guard stillSelected(selection) else { throw failure("The selected field changed. Select the text and try again.") }
                let board = NSPasteboard.general
                let saved = (board.pasteboardItems ?? []).map { item -> [NSPasteboard.PasteboardType: Data] in
                    Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
                }
                var ownedChange: Int?
                defer {
                    // Never overwrite a newer clipboard copied by the user or another app.
                    if let ownedChange, board.changeCount == ownedChange {
                        board.clearContents()
                        let restored = saved.map { data in
                            let item = NSPasteboardItem()
                            for (type, value) in data { item.setData(value, forType: type) }
                            return item
                        }
                        if !restored.isEmpty { board.writeObjects(restored) }
                    }
                }
                var original = selection.text
                if original == nil {
                    board.clearContents()
                    ownedChange = board.changeCount
                    postCommand(8) // C: fallback only when AX confirms a nonempty selection.
                    for _ in 0..<30 {
                        try await Task.sleep(for: .milliseconds(20))
                        if board.changeCount != ownedChange { break }
                        guard stillSelected(selection) else { throw failure("The selected field changed during copy.") }
                    }
                    guard board.changeCount != ownedChange,
                          let copied = board.string(forType: .string), !copied.isEmpty else {
                        throw failure("This field did not provide its selected text.")
                    }
                    original = copied
                    ownedChange = board.changeCount
                }
                guard let original, !original.isEmpty, let converter else {
                    throw failure("Select the text you want to correct first.")
                }
                let result = converter.convert(original, to: target)
                guard stillSelected(selection) else { throw failure("The selected field changed before replacement.") }
                if result.text != original {
                    let beforeValue = attribute(selection.element, kAXValueAttribute) as? String
                    let expectedValue: String? = {
                        guard let beforeValue, let range = selection.range,
                              range.location >= 0, range.length >= 0,
                              range.location + range.length <= (beforeValue as NSString).length else { return nil }
                        return (beforeValue as NSString).replacingCharacters(in:
                            NSRange(location: range.location, length: range.length), with: result.text)
                    }()
                    // Use the host's normal Paste operation, preserving its undo stack.
                    // Plain text replaces only the selection; no Return/submit is sent.
                    board.clearContents()
                    board.setString(result.text, forType: .string)
                    ownedChange = board.changeCount
                    postCommand(9) // V
                    var verified = false
                    for _ in 0..<25 {
                        try await Task.sleep(for: .milliseconds(20))
                        guard sameFocusedField(selection) else {
                            throw failure("Focus changed during replacement; the keyboard layout was not changed.")
                        }
                        if let expectedValue {
                            if attribute(selection.element, kAXValueAttribute) as? String == expectedValue {
                                verified = true
                                break
                            }
                        } else if let range = selectedRange(selection.element), range.length == 0,
                                  range.location == (selection.range?.location ?? -1) + result.text.utf16.count {
                            verified = true
                            break
                        }
                    }
                    if !verified {
                        // A custom control may accept Paste but expose no readable
                        // value. Do not paste twice or claim verified completion.
                        throw failure("Could not verify replacement in this field. Check the text; the layout was not changed.")
                    }
                }
                guard sameFocusedField(selection) else {
                    throw failure("Focus changed; the keyboard layout was not changed.")
                }
                try switchSource()
                if result.text != original {
                    // Switch as soon as verified, then let the app finish reading
                    // pasteboard data before restoring the user's clipboard.
                    try await Task.sleep(for: .milliseconds(100))
                }
            } catch {
                onError?(error.localizedDescription)
                NSSound.beep()
            }
        }
    }

    private func sameFocusedField(_ selection: SelectedTextTarget) -> Bool {
        guard !IsSecureEventInputEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.application.processIdentifier else { return false }
        let app = AXUIElementCreateApplication(selection.application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let focused = attribute(app, kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        return CFEqual(focused, selection.element)
    }

    private func stillSelected(_ selection: SelectedTextTarget) -> Bool {
        guard !IsSecureEventInputEnabled(), NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.application.processIdentifier,
              let current = captureSelection(in: selection.application), CFEqual(current.element, selection.element) else { return false }
        if let expected = selection.range {
            guard let actual = current.range, actual.location == expected.location, actual.length == expected.length else { return false }
        }
        if let text = selection.text, current.text != text { return false }
        if selection.range == nil, let marker = selection.markerRange {
            guard let currentMarker = current.markerRange, CFEqual(marker, currentMarker) else { return false }
        }
        return true
    }

    private func postCommand(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let raw = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        guard AXValueGetType(value) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "GlobeSwitch.TextCorrection", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
