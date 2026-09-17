import Foundation

/// Resolves the independent selection representations exposed by a text field.
/// A collapsed numeric range does not invalidate nonempty selected text.
public struct SelectionEvidence {
    public let text: String?
    public let range: NSRange?
    public var hasSelection: Bool { text != nil || range != nil }

    public init(text: String?, markerText: String?, range: NSRange?) {
        self.text = [text, markerText].compactMap { $0 }.first { !$0.isEmpty }
        // Do not use a contradictory range to calculate the expected pasted value.
        if let range, range.location >= 0, range.location != NSNotFound,
           range.length > 0,
           self.text.map({ $0.utf16.count == range.length }) ?? true {
            self.range = range
        } else {
            self.range = nil
        }
    }
}
