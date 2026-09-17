import Foundation
import Testing
@testable import GlobeSwitchCore

@Test func collapsedRangeDoesNotHideSelectedText() {
    let evidence = SelectionEvidence(text: "ghbdsn", markerText: nil,
                                     range: NSRange(location: 0, length: 0))
    #expect(evidence.hasSelection)
    #expect(evidence.text == "ghbdsn")
    #expect(evidence.range == nil)
}

@Test func emptyDirectTextFallsBackToMarkerText() {
    let evidence = SelectionEvidence(text: "", markerText: "ghbdsn",
                                     range: NSRange(location: 0, length: 0))
    #expect(evidence.hasSelection)
    #expect(evidence.text == "ghbdsn")
    #expect(evidence.range == nil)
}

@Test func copyFallbackRequiresANonemptyRange() {
    let selected = SelectionEvidence(text: "", markerText: nil,
                                    range: NSRange(location: 5, length: 6))
    #expect(selected.hasSelection)
    #expect(selected.text == nil)
    #expect(selected.range == NSRange(location: 5, length: 6))
    for range: NSRange? in [nil, NSRange(location: 5, length: 0), NSRange(location: NSNotFound, length: 6)] {
        #expect(!SelectionEvidence(text: "", markerText: "", range: range).hasSelection)
    }
}

@Test func replacementRangeMustMatchSelectedTextUTF16Length() {
    let text = "🙂a"
    let valid = SelectionEvidence(text: text, markerText: nil, range: NSRange(location: 4, length: 3))
    #expect(valid.range == NSRange(location: 4, length: 3))
    let conflicting = SelectionEvidence(text: text, markerText: nil, range: NSRange(location: 4, length: 2))
    #expect(conflicting.text == text)
    #expect(conflicting.range == nil)
}
