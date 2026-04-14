import CoreGraphics
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

/// Synthesises a Cmd+V key event to paste the current pasteboard contents
/// into the frontmost application.
///
/// Requires Accessibility permission (`AXIsProcessTrusted()`).  The legacy
/// implementation lives in `legacy/Source/AppController.m -pasteFromClipboard`.
actor PasteService {
    private static let log = Logger(subsystem: "com.naotaka.ClipMenu", category: "PasteService")
    static let simulatedPasteNotification = Notification.Name("PasteService.simulatedPasteNotification")
    private var cachedVKeyCode: CGKeyCode?
    private var loggedMissingAXThisSession = false

    struct AccessibilityStatus {
        let isTrusted: Bool
        let bundleIdentifier: String
        let executablePath: String
    }

    init() {
        NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.invalidateCachedKeyCode() }
        }
    }

    func paste() async {
        if Self.isPasteUITestMode {
            await MainActor.run {
                let value = NSPasteboard.general.string(forType: .string) ?? ""
                NotificationCenter.default.post(
                    name: Self.simulatedPasteNotification,
                    object: nil,
                    userInfo: ["string": value]
                )
            }
            return
        }

        guard isAccessibilityTrusted() else {
            Self.log.error("Paste aborted: Accessibility permission not granted")
            return
        }
        guard let keyCode = vKeyCode() else {
            Self.log.error("Paste aborted: could not resolve V key code")
            return
        }
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Self.log.error("Paste aborted: could not create CGEventSource")
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Self.log.info("Posted Cmd+V events using keyCode=\(keyCode, privacy: .public)")
    }

    nonisolated static func accessibilityStatus() -> AccessibilityStatus {
        AccessibilityStatus(
            isTrusted: isPasteUITestMode ? true : AXIsProcessTrusted(),
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "<nil>",
            executablePath: Bundle.main.executableURL?.path ?? "<unknown>"
        )
    }

    nonisolated private static var isPasteUITestMode: Bool {
        ProcessInfo.processInfo.environment["CLIPMENU_UI_TEST_MODE"] == "1"
    }

    private func isAccessibilityTrusted() -> Bool {
        if Self.accessibilityStatus().isTrusted {
            return true
        }

        if !loggedMissingAXThisSession {
            loggedMissingAXThisSession = true
            let status = Self.accessibilityStatus()
            Self.log.error("Accessibility permission missing. bundleID=\(status.bundleIdentifier, privacy: .public) execPath=\(status.executablePath, privacy: .public)")
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func invalidateCachedKeyCode() {
        cachedVKeyCode = nil
    }

    private func vKeyCode() -> CGKeyCode? {
        if let cachedVKeyCode {
            return cachedVKeyCode
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let layout = unsafeBitCast(layoutData, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layout) else {
            cachedVKeyCode = 9
            return cachedVKeyCode
        }

        let keyboardLayout = UnsafePointer<UCKeyboardLayout>(OpaquePointer(bytes))

        for keyCode in 0..<128 {
            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length = 0

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else { continue }
            let mapped = String(utf16CodeUnits: chars, count: Int(length))
            if mapped.caseInsensitiveCompare("v") == .orderedSame {
                cachedVKeyCode = CGKeyCode(keyCode)
                return cachedVKeyCode
            }
        }

        cachedVKeyCode = 9
        return cachedVKeyCode
    }
}
