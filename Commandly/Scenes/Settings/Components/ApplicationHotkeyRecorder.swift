import AppKit
import DesignSystem
import SwiftUI

struct ApplicationHotkeyRecorder: View {
    let hotKey: LauncherHotKey?
    let isDisabled: Bool
    let accessibilityTitle: String
    let onChange: (LauncherHotKey?) -> Void

    init(
        hotKey: LauncherHotKey?,
        isDisabled: Bool,
        accessibilityTitle: String = "application",
        onChange: @escaping (LauncherHotKey?) -> Void
    ) {
        self.hotKey = hotKey
        self.isDisabled = isDisabled
        self.accessibilityTitle = accessibilityTitle
        self.onChange = onChange
    }

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 5) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                        .commandlyFont(size: 9.5, weight: .semibold)
                    Text(isRecording ? "Type…" : (hotKey?.displayTitle ?? "Record"))
                        .commandlyFont(size: 10, weight: .medium)
                        .lineLimit(1)
                }
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .frame(minWidth: 72)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.55 : 1)
            .accessibilityLabel(
                isRecording
                    ? "Press a keyboard shortcut for \(accessibilityTitle)"
                    : "Record shortcut for \(accessibilityTitle)"
            )

            if hotKey != nil {
                Button {
                    stopRecording()
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark")
                        .commandlyFont(size: 9, weight: .semibold)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear shortcut for \(accessibilityTitle)")
            }
        }
        .animation(reduceMotion ? nil : CommandlyMotion.control, value: isRecording)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            if event.keyCode == 51 || event.keyCode == 117 {
                onChange(nil)
                stopRecording()
                return nil
            }
            let hotKey = LauncherHotKey(
                keyCode: event.keyCode,
                modifiers: LauncherHotKeyModifiers(event.modifierFlags)
            )
            guard hotKey.isValid else { return nil }
            onChange(hotKey)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}

private extension LauncherHotKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: LauncherHotKeyModifiers = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }
}
