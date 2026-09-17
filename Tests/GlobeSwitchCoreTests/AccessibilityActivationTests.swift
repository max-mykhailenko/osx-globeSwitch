import ApplicationServices
import Testing
@testable import GlobeSwitchCore

@Test func chromiumFallbackRunsWhenElectronAttributeIsUnsupported() {
    var calls: [String] = []
    let result = AccessibilityActivation.request { attribute in
        calls.append(attribute)
        return attribute == "AXManualAccessibility" ? .attributeUnsupported : .success
    }
    #expect(calls == ["AXManualAccessibility", "AXEnhancedUserInterface"])
    #expect(result.attribute == "AXEnhancedUserInterface")
    #expect(result.status == .success)
}

@Test func acceptedElectronRequestDoesNotEnableAnotherMode() {
    var calls: [String] = []
    let result = AccessibilityActivation.request { attribute in
        calls.append(attribute)
        return .success
    }
    #expect(calls == ["AXManualAccessibility"])
    #expect(result.status == .success)
}

@Test func activationDoesNotFallbackOnPermissionFailureOrTimeout() {
    for failure: AXError in [.apiDisabled, .cannotComplete, .failure] {
        var calls = 0
        let result = AccessibilityActivation.request { _ in
            calls += 1
            return failure
        }
        #expect(calls == 1)
        #expect(result.status == failure)
    }
}

@Test func unsupportedNativeAppKeepsTheFinalActivationError() {
    let result = AccessibilityActivation.request { _ in .attributeUnsupported }
    #expect(result.attribute == "AXEnhancedUserInterface")
    #expect(result.status == .attributeUnsupported)
}
