import AppKit
import SwiftUI

struct SearchPanelContent: View {
    @ObservedObject var coordinator: SearchCoordinator
    @FocusState private var isSearchFocused: Bool
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $coordinator.query, isFocused: $isSearchFocused) {
                coordinator.performSearchImmediately()
            }
            .onChange(of: coordinator.query) { _, newValue in
                coordinator.onQueryChanged(newValue)
            }

            Divider()

            ResultsList(
                results: coordinator.rankedResults,
                selectedIndex: $coordinator.selectedIndex,
                state: coordinator.state,
                statusMessage: coordinator.statusMessage,
                isUsingFallbackRanking: coordinator.isUsingFallbackRanking
            )
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Text("↵ open")
                Text("⌘↵ reveal")
                Text("esc close")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 680, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            isSearchFocused = true
            coordinator.onQueryChanged(coordinator.query)
        }
    }
}

/// Borderless NSPanel subclass that can become key window (required for keyboard input).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class SearchPanelController: NSObject {
    private var panel: KeyablePanel?
    private var hostingView: NSHostingView<AnyView>?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private let coordinator: SearchCoordinator

    init(coordinator: SearchCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        centerPanel(panel)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()

        installMonitors()
    }

    func hide() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    private func createPanel() {
        let content = SearchPanelContent(coordinator: coordinator) { [weak self] in
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: AnyView(content))
        hostingView.frame = NSRect(x: 0, y: 0, width: 680, height: 500)

        let panel = KeyablePanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
    }

    private func centerPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func installMonitors() {
        removeMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            switch event.keyCode {
            case 53: // Escape
                self.hide()
                return nil
            case 126: // Up
                self.coordinator.moveSelection(delta: -1)
                return nil
            case 125: // Down
                self.coordinator.moveSelection(delta: 1)
                return nil
            case 36: // Return
                if event.modifierFlags.contains(.command) {
                    self.coordinator.openSelected(revealInFinder: true)
                } else {
                    self.coordinator.openSelected(revealInFinder: false)
                    self.hide()
                }
                return nil
            default:
                return event
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let mouseLocation = NSEvent.mouseLocation
            if !panel.frame.contains(mouseLocation) {
                self.hide()
            }
        }
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
