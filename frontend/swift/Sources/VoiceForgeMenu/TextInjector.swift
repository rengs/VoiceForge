import AppKit
import ApplicationServices

final class TextInjector {
    enum InjectionError: LocalizedError {
        case accessibilityDenied
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "请在系统设置 → 隐私与安全性 → 辅助功能中允许 VoiceForge。"
            case .eventCreationFailed:
                return "无法创建粘贴键盘事件。"
            }
        }
    }

    static func currentSelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return nil
        }
        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            &selection
        ) == .success else {
            return nil
        }
        return selection as? String
    }

    func inject(_ text: String) throws {
        guard AXIsProcessTrusted() else {
            throw InjectionError.accessibilityDenied
        }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let insertedChangeCount = pasteboard.changeCount

        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
            )
        else {
            throw InjectionError.eventCreationFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard pasteboard.changeCount == insertedChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { values -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
