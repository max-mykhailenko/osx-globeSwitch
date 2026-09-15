import Testing
@testable import GlobeSwitchCore

@Test func globePressTriggersOnlyOnDownTransition() {
    var state = GlobePressState()
    let firstDown = state.update(isDown: true)
    let repeatedDown = state.update(isDown: true)
    let release = state.update(isDown: false)
    let secondDown = state.update(isDown: true)
    #expect(firstDown)
    #expect(!repeatedDown)
    #expect(!release)
    #expect(secondDown)
}

@Test func cycleAdvancesAndWrapsAcrossThreeSources() {
    let cycle = InputSourceCycle(sourceIDs: ["EN", "UA", "DE"])
    #expect(cycle.nextID(currentID: "EN") == "UA")
    #expect(cycle.nextID(currentID: "UA") == "DE")
    #expect(cycle.nextID(currentID: "DE") == "EN")
    #expect(cycle.nextID(currentID: "FR") == "EN")
    #expect(cycle.nextID(currentID: nil) == "EN")
}

@Test func emptyCycleHasNoNextSource() {
    #expect(InputSourceCycle(sourceIDs: []).nextID(currentID: nil) == nil)
}

@Test func selectionUsesAvailableOrderAndDropsUnavailableSources() {
    let reconciled = InputSourceSelection.reconcile(
        availableIDs: ["EN", "UA", "DE"],
        preferredIDs: ["DE", "EN", "MISSING"]
    )
    #expect(reconciled == ["EN", "DE"])
}

@Test func selectionFallsBackToAllAvailableWhenFewerThanTwoRemain() {
    let reconciled = InputSourceSelection.reconcile(
        availableIDs: ["EN", "UA", "DE"],
        preferredIDs: ["MISSING", "UA"]
    )
    #expect(reconciled == ["EN", "UA", "DE"])
}

@Test func selectionKeepsTheOnlyAvailableSourceVisible() {
    let reconciled = InputSourceSelection.reconcile(
        availableIDs: ["EN"],
        preferredIDs: ["MISSING"]
    )
    #expect(reconciled == ["EN"])
}

@Test @MainActor func correctsWrongLayoutInBothDirections() throws {
    let correction = try LayoutCorrection()
    #expect(correction.convert("руддщ", to: .english).text == "hello")
    #expect(correction.convert("ghbdsn", to: .ukrainian).text == "привіт")
    #expect(correction.convert("Руддщ", to: .english).text == "Hello")
    #expect(correction.convert("Ghbdsn", to: .ukrainian).text == "Привіт")
}

@Test @MainActor func directionIsExplicitAndUnmappedCharactersSurvive() throws {
    let correction = try LayoutCorrection()
    #expect(correction.convert("руддщ hello 👩🏽‍💻\n123", to: .english).text == "hello hello 👩🏽‍💻\n123")
    #expect(correction.convert("ghbdsn привіт", to: .ukrainian).text == "привіт привіт")
    #expect(correction.convert("hello", to: .english).text == "hello")
    #expect(correction.convert("", to: .ukrainian).text == "")
    #expect(correction.convert("hello", to: .ukrainian).target == .ukrainian)
}

@Test @MainActor func roundTripsAlphabetAndKeyboardPunctuation() throws {
    let correction = try LayoutCorrection()
    let alphabet = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM"
    let ukrainian = correction.convert(alphabet, to: .ukrainian).text
    #expect(correction.convert(ukrainian, to: .english).text == alphabet)
    #expect(correction.convert("[];',.", to: .ukrainian).text == "хїжєбю")
    #expect(correction.convert("хїжєбю", to: .english).text == "[];',.")
    #expect(correction.convert(" \n\t🙂", to: .english).text == " \n\t🙂")
}
