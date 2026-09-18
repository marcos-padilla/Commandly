import CommandKit

private enum VisualAIAction {
    static let capture = CommandActionID(rawValue: "visual-ai.capture")
    static let send = CommandActionID(rawValue: "visual-ai.send")
    static let remove = CommandActionID(rawValue: "visual-ai.remove")
    static let cancel = CommandActionID(rawValue: "visual-ai.cancel")
}
extension VisualAIModel: LauncherApplicationModel {
    var statusMessage: String? { message }
    var footerActions: [CommandActionDescriptor] {
        if isWorking { return [.init(id: VisualAIAction.cancel, title: "Cancel", isPrimary: true, keyHint: .escape)] }
        if image == nil { return [.init(id: VisualAIAction.capture, title: "Capture", isPrimary: true, keyHint: .return)] }
        return [.init(id: VisualAIAction.send, title: "Send Screenshot", isPrimary: true, keyHint: .init(symbols: ["⌘", "↩"]), isEnabled: canSend)]
    }
    var menuActions: [CommandActionDescriptor] {
        [.init(id: VisualAIAction.capture, title: "Capture Again", isEnabled: !isWorking),
         .init(id: VisualAIAction.remove, title: "Remove Image", isEnabled: image != nil),
         .init(id: VisualAIAction.cancel, title: "Cancel", isEnabled: isWorking)]
    }
    func moveSelection(offset: Int) {}
    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case VisualAIAction.capture: capture()
        case VisualAIAction.send: send()
        case VisualAIAction.remove: clearImage()
        case VisualAIAction.cancel: cancel()
        case BuiltInCommandActionID.openActions: showsActionsMenu.toggle()
        default: break
        }
    }
    func handleEscape() -> Bool {
        if isWorking { cancel(); return true }
        if showsActionsMenu { showsActionsMenu = false; return true }
        return false
    }
}
