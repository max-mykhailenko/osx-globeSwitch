import ApplicationServices

/// Negotiates the renderer's existing accessibility API, not macOS permissions.
public struct AccessibilityActivation {
    public let attribute: String
    public let status: AXError

    public static func request(setEnabled: (String) -> AXError) -> Self {
        let manual = "AXManualAccessibility"
        let manualStatus = setEnabled(manual)
        // Chromium does not implement Electron's manual attribute. Only try its
        // alternative when the first attribute is explicitly unsupported, never
        // to work around permission failures or timeouts.
        guard manualStatus == .attributeUnsupported else {
            return Self(attribute: manual, status: manualStatus)
        }
        let enhanced = "AXEnhancedUserInterface"
        return Self(attribute: enhanced, status: setEnabled(enhanced))
    }
}
