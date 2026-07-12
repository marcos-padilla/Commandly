import SwiftUI
import DesignSystem

struct OnboardingRootView: View {
    @State private var viewModel: OnboardingViewModel

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                OnboardingBackdrop()

                stepContent
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        )
                    )
                    .id(viewModel.step)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            OnboardingFooter(
                stepIndex: viewModel.stepIndex,
                stepCount: viewModel.stepCount,
                showsBackButton: viewModel.canGoBack,
                showsPrimaryAction: viewModel.showsPrimaryAction,
                primaryTitle: viewModel.primaryActionTitle,
                onBack: { viewModel.goBack() },
                onPrimary: { viewModel.advance() }
            )
        }
        .frame(
            minWidth: LayoutConstants.onboardingMinWidth,
            idealWidth: LayoutConstants.onboardingIdealWidth,
            minHeight: LayoutConstants.onboardingMinHeight,
            idealHeight: LayoutConstants.onboardingIdealHeight
        )
        .animation(.easeInOut(duration: MotionDuration.normal.rawValue), value: viewModel.step)
        .animation(.easeInOut(duration: MotionDuration.fast.rawValue), value: viewModel.hotkeyPhase)
        .preferredColorScheme(.dark)
        .compactWindowChrome(hidesZoomButton: true)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .welcome:
            WelcomeOnboardingStep()
        case .features:
            FeaturesOnboardingStep(features: viewModel.features)
        case .preferences:
            SetupOnboardingStep(viewModel: viewModel)
        case .permissions:
            PermissionsOnboardingStep(viewModel: viewModel)
        case .ready:
            ReadyOnboardingStep(viewModel: viewModel)
        }
    }
}

#Preview("Ready") {
    OnboardingRootView(viewModel: .preview(step: .ready))
}
