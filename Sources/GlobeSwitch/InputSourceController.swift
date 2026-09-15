import Carbon
import Foundation
import GlobeSwitchCore

struct InputSourceSummary: Equatable, Sendable {
    let id: String
    let name: String
    let abbreviation: String
}

struct SwitchMeasurement: Sendable {
    let source: InputSourceSummary
    let durationMilliseconds: Double
}

enum InputSourceError: LocalizedError {
    case insufficientSelectedSources
    case selectedSourceUnavailable(String)
    case currentSourceUnavailable
    case selectionFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .insufficientSelectedSources:
            "Select at least two input sources for the Globe cycle."
        case .selectedSourceUnavailable(let id):
            "The selected input source is no longer available: \(id)"
        case .currentSourceUnavailable:
            "The current keyboard input source could not be read."
        case .selectionFailed(let status):
            "macOS rejected the input-source change (OSStatus \(status))."
        }
    }
}

final class InputSourceController {
    private var sourcesByID: [String: TISInputSource] = [:]
    private(set) var availableSources: [InputSourceSummary] = []

    init() {
        reload()
    }

    func reload() {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as Any,
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true
        ]

        guard let unmanaged = TISCreateInputSourceList(filter as CFDictionary, false),
              let sources = unmanaged.takeRetainedValue() as? [TISInputSource] else {
            sourcesByID = [:]
            availableSources = []
            return
        }

        var refreshed: [String: TISInputSource] = [:]
        var summaries: [InputSourceSummary] = []
        for source in sources {
            guard let id = stringProperty(source, kTISPropertyInputSourceID) else { continue }
            guard refreshed[id] == nil else { continue }
            refreshed[id] = source
            if let summary = summary(for: source) {
                summaries.append(summary)
            }
        }
        sourcesByID = refreshed
        availableSources = summaries
    }

    func currentSource() -> InputSourceSummary? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return summary(for: source)
    }

    func toggle(selectedIDs: [String]) throws -> SwitchMeasurement {
        var cycleIDs = selectedIDs.filter { sourcesByID[$0] != nil }
        if cycleIDs.count < 2 {
            reload()
            cycleIDs = selectedIDs.filter { sourcesByID[$0] != nil }
        }
        guard cycleIDs.count >= 2 else {
            throw InputSourceError.insufficientSelectedSources
        }

        guard let current = currentSource() else {
            throw InputSourceError.currentSourceUnavailable
        }
        guard let nextID = InputSourceCycle(sourceIDs: cycleIDs).nextID(currentID: current.id) else {
            throw InputSourceError.insufficientSelectedSources
        }
        guard let next = sourcesByID[nextID] else {
            throw InputSourceError.selectedSourceUnavailable(nextID)
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let status = TISSelectInputSource(next)
        let end = DispatchTime.now().uptimeNanoseconds
        guard status == noErr else {
            throw InputSourceError.selectionFailed(status)
        }

        guard let selected = summary(for: next) else {
            throw InputSourceError.currentSourceUnavailable
        }
        return SwitchMeasurement(
            source: selected,
            durationMilliseconds: Double(end - start) / 1_000_000
        )
    }

    func nextSource(selectedIDs: [String]) throws -> InputSourceSummary {
        guard selectedIDs.count >= 2,
              let id = InputSourceCycle(sourceIDs: selectedIDs).nextID(currentID: currentSource()?.id),
              let source = availableSources.first(where: { $0.id == id }) else {
            throw InputSourceError.insufficientSelectedSources
        }
        return source
    }

    func select(id: String) throws -> SwitchMeasurement {
        guard let source = sourcesByID[id] else { throw InputSourceError.selectedSourceUnavailable(id) }
        let start = DispatchTime.now().uptimeNanoseconds
        let status = TISSelectInputSource(source)
        guard status == noErr else { throw InputSourceError.selectionFailed(status) }
        guard let selected = summary(for: source) else { throw InputSourceError.currentSourceUnavailable }
        return SwitchMeasurement(source: selected,
            durationMilliseconds: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }

    private func summary(for source: TISInputSource) -> InputSourceSummary? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        let abbreviation = abbreviation(for: source, name: name)
        return InputSourceSummary(id: id, name: name, abbreviation: abbreviation)
    }

    private func abbreviation(for source: TISInputSource, name: String) -> String {
        if let language = stringArrayProperty(source, kTISPropertyInputSourceLanguages)?.first {
            let code = language
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first
                .map(String.init)?
                .lowercased()
            if code == "uk" { return "UA" }
            if let code, !code.isEmpty { return String(code.prefix(2)).uppercased() }
        }

        let letters = name.unicodeScalars.filter(CharacterSet.letters.contains)
        let fallback = String(String.UnicodeScalarView(letters.prefix(2))).uppercased()
        return fallback.isEmpty ? "?" : fallback
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? String
    }

    private func stringArrayProperty(_ source: TISInputSource, _ key: CFString) -> [String]? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? [String]
    }
}
