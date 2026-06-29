import SwiftUI

@main
struct HayStackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("HayStack", systemImage: "magnifyingglass") {
            Button("Search") {
                appDelegate.toggleSearchPanel()
            }
            .keyboardShortcut(" ", modifiers: [.option])

            Button("Settings...") {
                appDelegate.openSettings()
            }

            Divider()

            Button("Quit HayStack") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
