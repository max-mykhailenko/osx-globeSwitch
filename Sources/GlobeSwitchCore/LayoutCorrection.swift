import Carbon
import Foundation

public enum CorrectionLanguage: String, Sendable {
    case english, ukrainian
    public var sourceID: String {
        self == .english ? "com.apple.keylayout.ABC" : "com.apple.keylayout.Ukrainian-PC"
    }
}

public struct CorrectionResult: Equatable, Sendable {
    public let text: String
    public let target: CorrectionLanguage
}

public enum LayoutCorrectionError: LocalizedError {
    case missingLayout(String)
    public var errorDescription: String? {
        switch self {
        case .missingLayout(let id): "Enable the ABC and Ukrainian-PC keyboard layouts in macOS Settings. Missing: \(id)"
        }
    }
}

/// Uses the output of the same physical key + Shift state in both layouts.
/// No dictionary, network request, or semantic rewriting is involved.
public struct LayoutCorrection {
    private let toUkrainian: [Character: Character]
    private let toEnglish: [Character: Character]

    public init() throws {
        let english = try Self.keyCharacters(id: CorrectionLanguage.english.sourceID)
        let ukrainian = try Self.keyCharacters(id: CorrectionLanguage.ukrainian.sourceID)
        var forward: [Character: Character] = [:]
        var backward: [Character: Character] = [:]
        for key in english.keys.sorted() {
            guard let en = english[key], let ua = ukrainian[key] else { continue }
            // Keep the primary ANSI key when a layout has duplicate outputs.
            if forward[en] == nil { forward[en] = ua }
            if backward[ua] == nil { backward[ua] = en }
        }
        toUkrainian = forward
        toEnglish = backward
    }

    public func convert(_ text: String, to target: CorrectionLanguage) -> CorrectionResult {
        let mapping = target == .english ? toEnglish : toUkrainian
        // Direction comes from the next source in the Globe cycle, not a guess
        // about whether the selected words make sense. Unmapped text is retained.
        return CorrectionResult(text: String(text.map { mapping[$0] ?? $0 }), target: target)
    }

    private static func keyCharacters(id: String) throws -> [Int: Character] {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            throw LayoutCorrectionError.missingLayout(id)
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)!).assumingMemoryBound(to: UCKeyboardLayout.self)
        var result: [Int: Character] = [:]
        // Printable main keyboard keys, then ISO/JIS extras. Exclude keypad,
        // navigation, and function keys, which create ambiguous duplicate output.
        for code in Array(0...50) + [93, 94, 102] {
            for shifted in 0...1 {
                var dead: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDown),
                    shifted == 1 ? UInt32(shiftKey >> 8) : 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let string = String(utf16CodeUnits: chars, count: length)
                guard string.count == 1, let character = string.first,
                      !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
                result[code * 2 + shifted] = character
            }
        }
        return result
    }
}
