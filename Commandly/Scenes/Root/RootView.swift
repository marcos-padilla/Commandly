import SwiftUI
import AppCore
import DesignSystem

struct RootView: View {
    @State private var viewModel: RootViewModel

    init(viewModel: RootViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: Spacing.lg.rawValue) {
            Text(viewModel.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.status)
                .font(.title2)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))

            Text(viewModel.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .frame(maxWidth: 420)
        }
        .padding(Spacing.xl.rawValue)
        .frame(
            minWidth: LayoutConstants.launcherMinWidth,
            minHeight: LayoutConstants.launcherMinHeight
        )
        .background(SemanticColors.color(for: .background))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.title). \(viewModel.status). \(viewModel.message)")
    }
}

#Preview {
    RootView(
        viewModel: RootViewModel(
            metadata: ApplicationMetadata(
                name: "Commandly",
                version: "1.0",
                build: "1",
                bundleIdentifier: "com.businessmate360.Commandly",
                environment: .development
            )
        )
    )
}
