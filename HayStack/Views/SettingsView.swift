import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: UserSettings
    @ObservedObject var coordinator: SearchCoordinator

    @State private var healthMessage: String = "Checking Ollama..."

    private let hotkeyPresets: [(name: String, keyCode: UInt32, modifiers: UInt32)] = [
        ("⌥ Space", UInt32(kVK_Space), UInt32(NSEvent.ModifierFlags.option.rawValue)),
        ("⌘ Space", UInt32(kVK_Space), UInt32(NSEvent.ModifierFlags.command.rawValue)),
        ("⌃ Space", UInt32(kVK_Space), UInt32(NSEvent.ModifierFlags.control.rawValue)),
        ("⌥ K", UInt32(kVK_ANSI_K), UInt32(NSEvent.ModifierFlags.option.rawValue)),
    ]

    var body: some View {
        Form {
            Section("Hotkey") {
                Picker("Global shortcut", selection: hotkeySelection) {
                    ForEach(hotkeyPresets, id: \.name) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
                Text("Current: \(settings.hotkeyDisplayString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ollama") {
                TextField("Endpoint", text: $settings.ollamaEndpoint)
                TextField("Model", text: $settings.ollamaModel)
                Stepper(value: $settings.maxResults, in: 5...100) {
                    Text("Max results: \(settings.maxResults)")
                }
                HStack {
                    Circle()
                        .fill(coordinator.ollamaHealth.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(healthMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Check Ollama Connection") {
                    Task {
                        await refreshHealth()
                    }
                }
            }

            Section("Search Scope") {
                Picker("Scope", selection: $settings.searchScope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
            }

            Section("Excluded Directories") {
                if settings.excludedDirectories.isEmpty {
                    Text("No excluded directories.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedDirectories, id: \.self) { path in
                        HStack {
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                settings.excludedDirectories.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button("Add Directory...") {
                    addExcludedDirectory()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
        .padding()
        .onAppear {
            Task { await refreshHealth() }
        }
        .onChange(of: settings.ollamaEndpoint) { _, _ in
            Task { await refreshHealth() }
        }
        .onChange(of: settings.ollamaModel) { _, _ in
            Task { await refreshHealth() }
        }
    }

    private var hotkeySelection: Binding<String> {
        Binding(
            get: {
                hotkeyPresets.first(where: {
                    $0.keyCode == settings.hotkeyKeyCode && $0.modifiers == settings.hotkeyModifiers
                })?.name ?? hotkeyPresets[0].name
            },
            set: { newValue in
                guard let preset = hotkeyPresets.first(where: { $0.name == newValue }) else { return }
                settings.hotkeyKeyCode = preset.keyCode
                settings.hotkeyModifiers = preset.modifiers
            }
        )
    }

    private func refreshHealth() async {
        await coordinator.refreshOllamaHealth()
        if coordinator.ollamaHealth.isRunning {
            if coordinator.ollamaHealth.selectedModelAvailable {
                healthMessage = "Connected. Model available."
            } else {
                healthMessage = coordinator.ollamaHealth.message ?? "Model not found."
            }
        } else {
            healthMessage = coordinator.ollamaHealth.message ?? "Ollama is not running."
        }
    }

    private func addExcludedDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Exclude"

        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !settings.excludedDirectories.contains(path) {
                settings.excludedDirectories.append(path)
            }
        }
    }
}
