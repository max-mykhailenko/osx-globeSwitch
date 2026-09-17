import AppKit
import Combine

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let controller: GlobeSwitchController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let iconProvider = SystemInputSourceIconProvider()
    private var cancellables: Set<AnyCancellable> = []

    private static let indicatorFont = NSFont.systemFont(
        ofSize: NSFont.systemFontSize,
        weight: .medium
    )
    private static let indicatorWidth = ceil(
        (":WW" as NSString).size(withAttributes: [.font: indicatorFont]).width
    )
    private static let systemIconWidth: CGFloat = 22

    init(controller: GlobeSwitchController) {
        self.controller = controller
        statusItem = NSStatusBar.system.statusItem(withLength: Self.indicatorWidth)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        controller.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)

        updateStatusItem()
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.captureMenuSelection()
        controller.refresh()
        rebuildMenu()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let active = controller.monitorState == .active
        let abbreviation = controller.currentSource?.abbreviation ?? "?"

        if let source = controller.currentSource,
           let image = iconProvider.image(for: source.id) {
            button.image = image
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.alignment = .center
            button.title = ""
            statusItem.length = Self.systemIconWidth
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.alignment = .left
            button.font = Self.indicatorFont
            button.title = ":\(abbreviation)"
            statusItem.length = Self.indicatorWidth
        }
        button.alphaValue = active ? 1 : 0.65
        button.setAccessibilityLabel("GlobeSwitch \(abbreviation)")
        button.toolTip = controller.errorText ?? monitorDescription
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        addDisabled("Current: \(controller.currentSource?.name ?? "Unknown")")
        addDisabled(monitorDescription)
        addDisabled(
            "Input Monitoring: \(controller.hasInputMonitoringPermission ? "Granted" : "Required")"
        )
        if let milliseconds = controller.lastSwitchMilliseconds {
            addDisabled(String(format: "Last direct switch: %.3f ms", milliseconds))
        }
        if let error = controller.errorText {
            let item = addDisabled(error)
            item.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
        }

        menu.addItem(.separator())
        let correction = NSMenuItem(title: "Correct Selected Text & Switch", action: #selector(correctSelection), keyEquivalent: "")
        correction.target = self
        correction.isEnabled = controller.hasMenuSelection && !controller.textCorrection.isBusy
        menu.addItem(correction)
        if controller.textCorrection.isBusy {
            addDisabled("Text correction is in progress.")
        } else if !controller.hasMenuSelection, let reason = controller.textCorrection.captureIssue {
            addDisabled(reason)
        }
        addDisabled("Globe: correct selection, otherwise switch")
        if !controller.textCorrection.hasPermission {
            let access = NSMenuItem(title: "Enable Text Correction — Accessibility…", action: #selector(requestTextPermission), keyEquivalent: "")
            access.target = self
            menu.addItem(access)
        }
        menu.addItem(.separator())
        addSourceSelectionMenu()
        menu.addItem(.separator())

        let pause = NSMenuItem(
            title: controller.isPaused ? "Resume Globe Switching" : "Pause Globe Switching",
            action: #selector(togglePaused),
            keyEquivalent: ""
        )
        pause.target = self
        menu.addItem(pause)

        if !controller.systemGlobeActionIsDisabled {
            let warning = addDisabled("Set ‘Press Globe key to’ → Do Nothing")
            warning.image = NSImage(
                systemSymbolName: "exclamationmark.triangle.fill",
                accessibilityDescription: nil
            )
            let settings = NSMenuItem(
                title: "Open Keyboard Settings…",
                action: #selector(openKeyboardSettings),
                keyEquivalent: ""
            )
            settings.target = self
            menu.addItem(settings)
        }

        if controller.monitorState != .active {
            let permission = NSMenuItem(
                title: "Request Keyboard Access…",
                action: #selector(requestPermission),
                keyEquivalent: ""
            )
            permission.target = self
            menu.addItem(permission)
        }

        let test = NSMenuItem(
            title: "Test Next Input Source",
            action: #selector(testSwitch),
            keyEquivalent: ""
        )
        test.target = self
        menu.addItem(test)

        let login = NSMenuItem(
            title: controller.launchAgentManager.isInstalled
                ? "Disable Launch at Login"
                : "Enable Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        login.target = self
        menu.addItem(login)

        let diagnostics = NSMenuItem(
            title: "Show Diagnostics Log",
            action: #selector(showDiagnostics),
            keyEquivalent: ""
        )
        diagnostics.target = self
        menu.addItem(diagnostics)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit GlobeSwitch", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func addSourceSelectionMenu() {
        let parent = NSMenuItem(
            title: "Input Sources in Globe Cycle",
            action: nil,
            keyEquivalent: ""
        )
        let sourceMenu = NSMenu(title: "Input Sources in Globe Cycle")

        if controller.availableSources.isEmpty {
            let empty = NSMenuItem(
                title: "No enabled input sources found",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            sourceMenu.addItem(empty)
        } else {
            for source in controller.availableSources {
                let item = NSMenuItem(
                    title: "\(source.abbreviation) — \(source.name)",
                    action: #selector(toggleSourceSelection(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = source.id
                item.state = controller.isSourceSelected(id: source.id) ? .on : .off
                sourceMenu.addItem(item)
            }
        }

        parent.submenu = sourceMenu
        menu.addItem(parent)
    }

    private var monitorDescription: String {
        if controller.isPaused {
            return "Globe monitor: Paused"
        }
        return switch controller.monitorState {
        case .stopped: "Globe monitor: Stopped"
        case .permissionRequired: "Globe monitor: Input Monitoring required"
        case .active: "Globe monitor: Active (switch on key-down)"
        case .failed(let message): "Globe monitor: \(message)"
        }
    }

    @discardableResult
    private func addDisabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    @objc private func correctSelection() {
        controller.correctFromMenu()
    }

    @objc private func requestTextPermission() {
        controller.textCorrection.requestPermission()
    }

    @objc private func requestPermission() {
        controller.requestKeyboardPermission()
    }

    @objc private func togglePaused() {
        controller.togglePaused()
        rebuildMenu()
    }

    @objc private func testSwitch() {
        controller.testSwitch()
    }

    @objc private func toggleSourceSelection(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        controller.toggleSourceSelection(id: id)
        rebuildMenu()
    }

    @objc private func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if controller.launchAgentManager.isInstalled {
                try controller.launchAgentManager.uninstall()
            } else {
                try controller.launchAgentManager.install()
            }
        } catch {
            DiagnosticsLogger.shared.log(error.localizedDescription, level: .error)
        }
        rebuildMenu()
    }

    @objc private func showDiagnostics() {
        NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsLogger.shared.logURL])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
