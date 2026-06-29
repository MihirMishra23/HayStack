import Foundation
import SwiftUI

enum SearchScope: String, CaseIterable, Identifiable {
    case homeDirectory
    case allVolumes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .homeDirectory: return "Home Directory"
        case .allVolumes: return "All Volumes"
        }
    }
}

@MainActor
final class UserSettings: ObservableObject {
    private enum Keys {
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let ollamaModel = "ollamaModel"
        static let ollamaEndpoint = "ollamaEndpoint"
        static let maxResults = "maxResults"
        static let excludedDirectories = "excludedDirectories"
        static let searchScope = "searchScope"
    }

    @Published var hotkeyKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode) }
    }

    @Published var hotkeyModifiers: UInt32 {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers) }
    }

    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel) }
    }

    @Published var ollamaEndpoint: String {
        didSet { UserDefaults.standard.set(ollamaEndpoint, forKey: Keys.ollamaEndpoint) }
    }

    @Published var maxResults: Int {
        didSet { UserDefaults.standard.set(maxResults, forKey: Keys.maxResults) }
    }

    @Published var excludedDirectories: [String] {
        didSet { UserDefaults.standard.set(excludedDirectories, forKey: Keys.excludedDirectories) }
    }

    @Published var searchScope: SearchScope {
        didSet { UserDefaults.standard.set(searchScope.rawValue, forKey: Keys.searchScope) }
    }

    var hotkeyDisplayString: String {
        HotkeyManager.displayString(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private static let optionRaw = Int(NSEvent.ModifierFlags.option.rawValue)

    init() {
        let defaults = UserDefaults.standard

        // Migrate bad modifier value from earlier builds
        let storedMod = defaults.integer(forKey: Keys.hotkeyModifiers)
        if storedMod != 0, !Self.isValidModifierFlags(storedMod) {
            defaults.removeObject(forKey: Keys.hotkeyModifiers)
        }

        self.hotkeyKeyCode = UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode).nonZeroOr(49)) // Space
        self.hotkeyModifiers = UInt32(defaults.integer(forKey: Keys.hotkeyModifiers).nonZeroOr(Self.optionRaw)) // Option
        self.ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.2:1b"
        self.ollamaEndpoint = defaults.string(forKey: Keys.ollamaEndpoint) ?? "http://localhost:11434"
        self.maxResults = defaults.object(forKey: Keys.maxResults) as? Int ?? 25
        self.excludedDirectories = defaults.stringArray(forKey: Keys.excludedDirectories) ?? []
        self.searchScope = SearchScope(rawValue: defaults.string(forKey: Keys.searchScope) ?? "") ?? .homeDirectory
    }

    private static func isValidModifierFlags(_ value: Int) -> Bool {
        let known: UInt = NSEvent.ModifierFlags.option.rawValue
            | NSEvent.ModifierFlags.command.rawValue
            | NSEvent.ModifierFlags.control.rawValue
            | NSEvent.ModifierFlags.shift.rawValue
        return UInt(value) & known != 0
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int {
        self == 0 ? fallback : self
    }
}
