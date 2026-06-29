import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = UserSettings()
    lazy var coordinator = SearchCoordinator(settings: settings)
    lazy var searchPanelController = SearchPanelController(coordinator: coordinator)
    lazy var hotkeyManager = HotkeyManager()

    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerHotkey()

        Task {
            await coordinator.refreshOllamaHealth()
            if !coordinator.ollamaHealth.isRunning {
                showOllamaAlertIfNeeded()
            }
        }
    }

    func toggleSearchPanel() {
        searchPanelController.toggle()
    }

    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, coordinator: coordinator)
                .onChange(of: settings.hotkeyKeyCode) { [weak self] _, _ in self?.registerHotkey() }
                .onChange(of: settings.hotkeyModifiers) { [weak self] _, _ in self?.registerHotkey() }

            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "HayStack Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 540, height: 520))
            window.center()
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func registerHotkey() {
        hotkeyManager.register(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        ) { [weak self] in
            self?.toggleSearchPanel()
        }
    }

    private func showOllamaAlertIfNeeded() {
        let alert = NSAlert()
        alert.messageText = "Ollama Not Running"
        alert.informativeText = """
        HayStack can still search files, but AI ranking requires Ollama.

        Install: brew install ollama
        Start: ollama serve
        Pull model: ollama pull \(settings.ollamaModel)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
