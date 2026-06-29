import AppKit
import Carbon.HIToolbox
import HotKey

@MainActor
final class HotkeyManager {
    private var hotKey: HotKey?
    private var onTrigger: (() -> Void)?

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))

        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        if let key = Key(carbonKeyCode: keyCode) {
            parts.append(key.description)
        } else {
            parts.append("Key\(keyCode)")
        }

        return parts.joined()
    }

    func register(keyCode: UInt32, modifiers: UInt32, onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
        hotKey = nil

        guard let key = Key(carbonKeyCode: keyCode) else { return }

        let hotKey = HotKey(key: key, modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers)))
        hotKey.keyDownHandler = { [weak self] in
            self?.onTrigger?()
        }
        self.hotKey = hotKey
    }
}
