import CommandKit
import Foundation
import Infrastructure
import Observation

enum OfflineToolsActionID {
    static let sampleColor = CommandActionID(rawValue: "offline-tools.sample-color")
    static let copyRGB = CommandActionID(rawValue: "offline-tools.copy-rgb")
    static let copyHSL = CommandActionID(rawValue: "offline-tools.copy-hsl")
    static let lookup = CommandActionID(rawValue: "offline-tools.lookup")
    static let resetTyping = CommandActionID(rawValue: "offline-tools.reset-typing")
}

@Observable
@MainActor
final class OfflineToolsViewModel {
    let tool: OfflineToolKind
    private let services: OfflineToolsServices
    private let onGoBack: () -> Void

    var query = "" {
        didSet { refreshSelection() }
    }
    var showsActionsMenu = false
    private(set) var statusMessage: String?
    private(set) var shouldScrollToSelection = false

    var selectedEmojiID: String?
    var textInput = ""
    var textCaseStyle: TextCaseStyle = .uppercase
    var colorInput = "#4A7DFF"
    var dictionaryDefinition: String?
    private(set) var isLookingUpDefinition = false
    var selectedFontFamily: String?
    var typingText = "" {
        didSet { updateTypingState(oldValue: oldValue) }
    }
    private(set) var typingStartedAt: Date?
    private(set) var typingCompletedAt: Date?

    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private var colorSamplingTask: Task<Void, Never>?

    init(
        tool: OfflineToolKind,
        services: OfflineToolsServices,
        onGoBack: @escaping () -> Void
    ) {
        self.tool = tool
        self.services = services
        self.onGoBack = onGoBack
        self.selectedEmojiID = EmojiCatalog.entries.first?.id
        self.selectedFontFamily = services.fontCatalog.availableFamilies.first
    }

    var filteredEmoji: [EmojiCatalogEntry] {
        EmojiCatalog.entries.filter { $0.matches(query) }
    }

    var selectedEmoji: EmojiCatalogEntry? {
        filteredEmoji.first(where: { $0.id == selectedEmojiID }) ?? filteredEmoji.first
    }

    var textOutput: String {
        TextCaseConverter.convert(textInput, to: textCaseStyle)
    }

    var parsedColor: CommandlyColor? {
        CommandlyColor(string: colorInput)
    }

    var filteredFonts: [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.isEmpty == false else { return services.fontCatalog.availableFamilies }
        return services.fontCatalog.availableFamilies.filter {
            $0.localizedCaseInsensitiveContains(needle)
        }
    }

    var typingResult: TypingPracticeResult {
        let startedAt = typingStartedAt ?? services.now()
        let finishedAt = typingCompletedAt ?? services.now()
        return TypingPracticeEngine.result(
            typed: typingText,
            elapsed: max(finishedAt.timeIntervalSince(startedAt), 0)
        )
    }

    var footerActions: [CommandActionDescriptor] {
        switch tool {
        case .dictionary:
            return [
                CommandActionDescriptor(
                    id: OfflineToolsActionID.lookup,
                    title: "Look Up",
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ),
                actionsDescriptor
            ]
        case .typing:
            return [
                CommandActionDescriptor(
                    id: OfflineToolsActionID.resetTyping,
                    title: "New Attempt",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        default:
            return [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.copy,
                    title: copyActionTitle,
                    isPrimary: true,
                    keyHint: .return,
                    isEnabled: copyValue != nil
                ),
                actionsDescriptor
            ]
        }
    }

    var menuActions: [CommandActionDescriptor] {
        switch tool {
        case .color:
            return [
                CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: "Copy Hex", isEnabled: parsedColor != nil),
                CommandActionDescriptor(id: OfflineToolsActionID.copyRGB, title: "Copy RGB", isEnabled: parsedColor != nil),
                CommandActionDescriptor(id: OfflineToolsActionID.copyHSL, title: "Copy HSL", isEnabled: parsedColor != nil),
                CommandActionDescriptor(id: OfflineToolsActionID.sampleColor, title: "Pick Screen Color")
            ]
        case .dictionary:
            return [
                CommandActionDescriptor(id: OfflineToolsActionID.lookup, title: "Look Up", isEnabled: query.isEmpty == false),
                CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: "Copy Definition", isEnabled: dictionaryDefinition != nil)
            ]
        case .typing:
            return [
                CommandActionDescriptor(id: OfflineToolsActionID.resetTyping, title: "New Attempt")
            ]
        default:
            return [
                CommandActionDescriptor(id: BuiltInCommandActionID.copy, title: copyActionTitle, isEnabled: copyValue != nil)
            ]
        }
    }

    func selectEmoji(_ id: String) {
        selectedEmojiID = id
        shouldScrollToSelection = false
        statusMessage = nil
    }

    func selectFont(_ family: String) {
        selectedFontFamily = family
        shouldScrollToSelection = false
        statusMessage = nil
    }

    func moveSelection(offset: Int) {
        switch tool {
        case .emoji:
            selectedEmojiID = LauncherListSelection.nextID(
                in: filteredEmoji,
                selectedID: selectedEmojiID,
                offset: offset,
                id: \.id
            )
        case .fonts:
            selectedFontFamily = LauncherListSelection.nextID(
                in: filteredFonts,
                selectedID: selectedFontFamily,
                offset: offset,
                id: { $0 }
            )
        default:
            return
        }
        shouldScrollToSelection = true
        statusMessage = nil
    }

    func perform(_ actionID: CommandActionID) {
        switch actionID {
        case BuiltInCommandActionID.copy:
            copy(copyValue, message: copyStatusMessage)
        case BuiltInCommandActionID.openActions:
            showsActionsMenu.toggle()
        case OfflineToolsActionID.copyRGB:
            copy(parsedColor?.rgb, message: "RGB copied.")
        case OfflineToolsActionID.copyHSL:
            copy(parsedColor?.hsl, message: "HSL copied.")
        case OfflineToolsActionID.sampleColor:
            sampleColor()
        case OfflineToolsActionID.lookup:
            lookupDefinition()
        case OfflineToolsActionID.resetTyping:
            resetTyping()
        case BuiltInCommandActionID.goBack:
            onGoBack()
        default:
            break
        }
    }

    func goBack() {
        onGoBack()
    }

    func handleEscape() -> Bool {
        switch tool {
        case .emoji, .dictionary, .fonts:
            guard query.isEmpty == false else { return false }
            query = ""
            return true
        case .textCase:
            guard textInput.isEmpty == false else { return false }
            textInput = ""
            return true
        case .color:
            return false
        case .typing:
            guard typingText.isEmpty == false else { return false }
            resetTyping()
            return true
        }
    }

    func stop() {
        lookupTask?.cancel()
        lookupTask = nil
        copyTask?.cancel()
        copyTask = nil
        colorSamplingTask?.cancel()
        colorSamplingTask = nil
    }

    func flushLookupForTesting() async {
        await lookupTask?.value
    }

    func flushCopyForTesting() async {
        await copyTask?.value
    }

    func lookupDefinition() {
        let word = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.isEmpty == false else { return }
        lookupTask?.cancel()
        isLookingUpDefinition = true
        dictionaryDefinition = nil
        statusMessage = nil
        lookupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let definition = await services.dictionary.definition(for: word)
            guard Task.isCancelled == false, query.trimmingCharacters(in: .whitespacesAndNewlines) == word else {
                return
            }
            isLookingUpDefinition = false
            dictionaryDefinition = definition
            if definition == nil {
                statusMessage = "No local definition found."
            }
        }
    }

    func sampleColor() {
        colorSamplingTask?.cancel()
        colorSamplingTask = Task { @MainActor [weak self] in
            guard let self, let color = await services.colorSampler.sample() else { return }
            guard Task.isCancelled == false else { return }
            colorInput = color.hex
            statusMessage = "Color sampled."
            showsActionsMenu = false
        }
    }

    func resetTyping() {
        typingText = ""
        typingStartedAt = nil
        typingCompletedAt = nil
        statusMessage = nil
    }

    private var actionsDescriptor: CommandActionDescriptor {
        CommandActionDescriptor(
            id: BuiltInCommandActionID.openActions,
            title: "Actions",
            keyHint: .commandK
        )
    }

    private var copyActionTitle: String {
        switch tool {
        case .emoji: return "Copy Emoji"
        case .textCase: return "Copy Converted Text"
        case .color: return "Copy Hex"
        case .fonts: return "Copy Font Name"
        case .dictionary: return "Copy Definition"
        case .typing: return "Copy Result"
        }
    }

    private var copyValue: String? {
        switch tool {
        case .emoji:
            return selectedEmoji?.symbol
        case .textCase:
            return textOutput.isEmpty ? nil : textOutput
        case .color:
            return parsedColor?.hex
        case .dictionary:
            return dictionaryDefinition
        case .fonts:
            return selectedFontFamily
        case .typing:
            return nil
        }
    }

    private var copyStatusMessage: String {
        switch tool {
        case .emoji: return "Emoji copied."
        case .textCase: return "Converted text copied."
        case .color: return "Hex color copied."
        case .dictionary: return "Definition copied."
        case .fonts: return "Font name copied."
        case .typing: return "Copied."
        }
    }

    private func copy(_ value: String?, message: String) {
        guard let value else { return }
        copyTask?.cancel()
        copyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await services.pasteboard.writeString(value)
            guard Task.isCancelled == false else { return }
            statusMessage = message
            showsActionsMenu = false
        }
    }

    private func refreshSelection() {
        switch tool {
        case .emoji:
            selectedEmojiID = LauncherListSelection.resolvedID(
                in: filteredEmoji,
                selectedID: selectedEmojiID,
                id: \.id
            )
        case .fonts:
            selectedFontFamily = LauncherListSelection.resolvedID(
                in: filteredFonts,
                selectedID: selectedFontFamily,
                id: { $0 }
            )
        default:
            break
        }
        if tool == .dictionary {
            dictionaryDefinition = nil
            isLookingUpDefinition = false
            lookupTask?.cancel()
        }
    }

    private func updateTypingState(oldValue: String) {
        if oldValue.isEmpty, typingText.isEmpty == false {
            typingStartedAt = services.now()
        }
        if typingText == TypingPracticeEngine.prompt, typingCompletedAt == nil {
            typingCompletedAt = services.now()
            statusMessage = "Practice complete."
        } else if typingText != TypingPracticeEngine.prompt {
            typingCompletedAt = nil
        }
    }
}
