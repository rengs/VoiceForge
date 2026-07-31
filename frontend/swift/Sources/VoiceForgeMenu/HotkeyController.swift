import AppKit

final class HotkeyController {
    enum HotkeyError: LocalizedError {
        case eventTapUnavailable

        var errorDescription: String? {
            "无法监听全局快捷键，请在系统设置中授予 VoiceForge 辅助功能权限。"
        }
    }

    private let pressed: () -> Void
    private let released: () -> Void
    private var eventTap: CFMachPort?
    private var source: CFRunLoopSource?
    private var isPressed = false

    init(pressed: @escaping () -> Void, released: @escaping () -> Void) {
        self.pressed = pressed
        self.released = released
    }

    func install() throws {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
        let eventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: Self.callback,
            userInfo: pointer
        ) else {
            throw HotkeyError.eventTapUnavailable
        }
        eventTap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        let required: CGEventFlags = [.maskCommand, .maskShift]

        if type == .flagsChanged,
           isPressed,
           event.flags.intersection(required) != required {
            isPressed = false
            DispatchQueue.main.async { [released] in released() }
            return
        }

        guard event.getIntegerValueField(.keyboardEventKeycode) == 49 else {
            return
        }

        if type == .keyDown,
           event.flags.intersection(required) == required,
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
           !isPressed {
            isPressed = true
            DispatchQueue.main.async { [pressed] in pressed() }
        } else if type == .keyUp, isPressed {
            isPressed = false
            DispatchQueue.main.async { [released] in released() }
        }
    }

    private static let callback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let controller = Unmanaged<HotkeyController>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        controller.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }
}
