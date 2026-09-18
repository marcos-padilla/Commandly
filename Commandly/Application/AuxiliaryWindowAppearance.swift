import Observation

/// Shares user-selected text sizing with independent native tool windows without replacing editors.
@Observable
@MainActor
final class AuxiliaryWindowAppearance {
    var textSize: AppTextSizePreference

    init(textSize: AppTextSizePreference = .standard) {
        self.textSize = textSize
    }
}
