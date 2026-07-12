import SwiftUI
import DesignSystem
import SecurityKit
import SecurityKit

/// Permissions step — explain first, then grant per capability. Skippable via Continue.
struct PermissionsOnboardingStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.xxl.rawValue)
                .padding(.top, Spacing.xxl.rawValue + Spacing.md.rawValue)
                .padding(.bottom, Spacing.xl.rawValue)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.permissionItems.enumerated()), id: \.element.id) { index, item in
                    PermissionAccessRow(
                        item: item,
                        status: viewModel.status(for: item),
                        onAction: { viewModel.handlePermissionAction(item) }
                    )

                    if index < viewModel.permissionItems.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.leading, 72)
                    }
                }
            }
            .padding(.vertical, Spacing.xs.rawValue)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .fill(BrandPalette.elevatedSurface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl.rawValue, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                BrandPalette.accent.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: BrandPalette.accent.opacity(0.10), radius: 24, y: 10)
            .padding(.horizontal, Spacing.xxl.rawValue)
            .frame(maxWidth: 720, alignment: .leading)

            Text("Everything here is optional. You can grant access now or enable features later in Settings.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .padding(.horizontal, Spacing.xxl.rawValue)
                .padding(.top, Spacing.md.rawValue)
                .frame(maxWidth: 720, alignment: .leading)

            Spacer(minLength: Spacing.lg.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            Task { await viewModel.preparePermissionsStep() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md.rawValue) {
            Text("Permissions")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(BrandPalette.accentSoft)
                .padding(.horizontal, Spacing.sm.rawValue)
                .padding(.vertical, Spacing.xxs.rawValue + 1)
                .background(
                    Capsule(style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )

            Text("Only what you need")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(SemanticColors.color(for: .primaryText))
                .accessibilityAddTraits(.isHeader)

            Text("Commandly asks for access when a feature needs it—and explains why first. Grant what you want now, skip the rest.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(SemanticColors.color(for: .secondaryText))
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionAccessRow: View {
    let item: OnboardingPermissionItem
    let status: OnboardingPermissionStatus
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md.rawValue) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(BrandPalette.accent.opacity(status.state == .authorized ? 0.30 : 0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BrandPalette.accentSoft)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs.rawValue) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SemanticColors.color(for: .primaryText))

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(SemanticColors.color(for: .secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm.rawValue)

            actionControl
        }
        .padding(.horizontal, Spacing.md.rawValue)
        .padding(.vertical, Spacing.md.rawValue)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.subtitle). \(status.actionTitle)")
    }

    @ViewBuilder
    private var actionControl: some View {
        if status.isRequesting {
            ProgressView()
                .controlSize(.small)
                .frame(width: 108, height: 30)
                .accessibilityLabel("Requesting \(item.title)")
        } else if status.state == .authorized {
            HStack(spacing: Spacing.xxs.rawValue) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandPalette.accentSoft)
                Text("Granted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SemanticColors.color(for: .primaryText))
            }
            .frame(minWidth: 108)
            .accessibilityLabel("\(item.title) granted")
        } else {
            Button(action: onAction) {
                Text(status.actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, Spacing.md.rawValue)
                    .padding(.vertical, Spacing.xs.rawValue)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                            .fill(
                                status.state == .denied || status.state == .restricted
                                    ? BrandPalette.accent.opacity(0.35)
                                    : Color.white.opacity(0.10)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!status.showsActionAsEnabled)
            .accessibilityLabel(status.actionTitle)
            .accessibilityHint(item.subtitle)
        }
    }
}

#Preview {
    PermissionsOnboardingStep(viewModel: .preview(step: .permissions))
        .frame(width: 960, height: 640)
        .background(OnboardingBackdrop())
        .preferredColorScheme(.dark)
}
