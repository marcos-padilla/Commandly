import DesignSystem
import SwiftUI

struct FinderAIView: View {
    @Bindable var viewModel: FinderAIViewModel
    @Environment(\.commandlyLayoutDensity) private var density
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LauncherPalette.detail)
            Rectangle()
                .fill(LauncherPalette.separator)
                .frame(height: 1)
            composer
        }
        .task {
            await viewModel.start()
            isPromptFocused = viewModel.phase == .ready
        }
        .onDisappear {
            viewModel.stop()
        }
        .accessibilityLabel("Finder AI")
    }

    private var header: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: viewModel.goBack)
            Image(systemName: "folder.badge.gearshape")
                .commandlyFont(size: 14, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: 26, height: 26)
                .background(BrandPalette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Finder AI")
                    .commandlyFont(size: 13, weight: .semibold)
                Text(viewModel.providerLabel ?? "Provider setup required")
                    .commandlyFont(size: 9)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: density.spacing(.sm))
            Label("Authorized folders only", systemImage: "lock.shield")
                .commandlyFont(size: 9, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.045), in: Capsule())
                .accessibilityLabel("Finder access is limited to folders authorized in Settings")
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.chrome)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.phase == .loading {
            VStack(spacing: density.spacing(.sm)) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing an isolated Finder session…")
                    .commandlyFont(size: 10.5)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if let message = viewModel.configurationMessage {
            configurationState(message)
        } else {
            conversation
        }
    }

    private func configurationState(_ message: String) -> some View {
        VStack(spacing: density.spacing(.sm)) {
            Image(systemName: viewModel.needsFolderAuthorization ? "folder.badge.plus" : "key.horizontal.fill")
                .commandlyFont(size: 25, weight: .medium)
                .foregroundStyle(.tertiary)
            Text(viewModel.needsFolderAuthorization ? "Choose Finder folders" : "Set up Finder AI")
                .commandlyFont(size: 13, weight: .semibold)
            Text(message)
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            HStack(spacing: density.spacing(.xs)) {
                Button(viewModel.needsFolderAuthorization ? "Open Permissions" : "Open AI Settings") {
                    viewModel.perform(
                        viewModel.needsFolderAuthorization
                            ? FinderAIActionID.openPermissionsSettings
                            : FinderAIActionID.openAISettings
                    )
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    viewModel.refreshConnection()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(density.spacing(.lg))
        .accessibilityElement(children: .contain)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: density.spacing(.sm)) {
                    if viewModel.entries.isEmpty {
                        welcome
                    }
                    ForEach(viewModel.entries) { entry in
                        message(entry)
                            .id(entry.id)
                    }
                    if let approval = viewModel.pendingApproval {
                        approvalCard(approval)
                            .id("finder-ai-approval")
                    } else if viewModel.phase == .responding {
                        thinking
                            .id("finder-ai-thinking")
                    }
                }
                .padding(density.spacing(.md))
            }
            .onChange(of: viewModel.entries.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.pendingApproval != nil) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: "sparkles")
                    .foregroundStyle(BrandPalette.accentSoft)
                Text("Ask about your authorized folders")
                    .commandlyFont(size: 12.5, weight: .semibold)
            }
            Text(
                "Finder AI can search, inspect metadata, reveal items, and propose file changes. "
                    + "Reading contents or changing files always pauses for your approval."
            )
            .commandlyFont(size: 10.5)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Label(viewModel.providerDisclosureMessage, systemImage: "network")
                .commandlyFont(size: 9.5)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(viewModel.providerDisclosureMessage)

            HStack(spacing: density.spacing(.xs)) {
                suggestion("Find recent PDFs about invoices")
                suggestion("Organize selected reports into a folder")
                suggestion("Show large files in my project folder")
            }
        }
        .padding(density.spacing(.md))
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func suggestion(_ text: String) -> some View {
        Button(text) {
            viewModel.draft = text
            isPromptFocused = true
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .lineLimit(1)
    }

    @ViewBuilder
    private func message(_ entry: FinderAIConversationEntry) -> some View {
        switch entry.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(entry.text)
                    .commandlyFont(size: 11.5)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(BrandPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(entry.text)")
        case .assistant:
            HStack(alignment: .top, spacing: density.spacing(.xs)) {
                Image(systemName: "sparkles")
                    .commandlyFont(size: 10, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
                    .frame(width: 22, height: 22)
                    .background(BrandPalette.accent.opacity(0.1), in: Circle())
                Text(entry.text)
                    .commandlyFont(size: 11.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 40)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Finder AI: \(entry.text)")
        case .activity:
            Label(entry.text, systemImage: "checkmark.circle")
                .commandlyFont(size: 9.5, weight: .medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 29)
        case .error:
            Label(entry.text, systemImage: "exclamationmark.triangle.fill")
                .commandlyFont(size: 10.5, weight: .medium)
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var thinking: some View {
        HStack(spacing: density.spacing(.xs)) {
            ProgressView()
                .controlSize(.mini)
            Text("Finder AI is working…")
                .commandlyFont(size: 10.5)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 29)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func approvalCard(_ approval: FinderAIToolApprovalRequest) -> some View {
        VStack(alignment: .leading, spacing: density.spacing(.sm)) {
            HStack(alignment: .top, spacing: density.spacing(.xs)) {
                Image(systemName: approvalSystemImage(approval))
                    .foregroundStyle(approvalTint(approval))
                VStack(alignment: .leading, spacing: 2) {
                    Text(approvalTitle(approval))
                        .commandlyFont(size: 12, weight: .semibold)
                    Text("Review this exact, one-time plan. Approval expires automatically.")
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                    if let providerName = viewModel.approvalProviderName {
                        Text("Requested through \(providerName)")
                            .commandlyFont(size: 9.5, weight: .medium)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            switch approval {
            case .textRead(_, let plan):
                ForEach(plan.items) { item in
                    approvalRow(
                        icon: "doc.text",
                        title: item.displayName,
                        detail: item.relativeLocation
                    )
                }
                Text("Up to \(ByteCountFormatter.string(fromByteCount: Int64(plan.maximumByteCount), countStyle: .file)) will be sent to \(viewModel.approvalProviderName ?? "the active provider").")
                    .commandlyFont(size: 9.5, weight: .medium)
                    .foregroundStyle(.orange)
            case .mutation(_, let plan):
                ForEach(plan.operations) { operation in
                    approvalRow(
                        icon: mutationIcon(operation.kind),
                        title: mutationTitle(operation),
                        detail: mutationDetail(operation)
                    )
                }
                if plan.warnings.isEmpty == false {
                    Text(plan.warnings.map(warningTitle).sorted().joined(separator: " · "))
                        .commandlyFont(size: 9.5, weight: .medium)
                        .foregroundStyle(plan.risk == .destructive ? .red : .orange)
                }
            }

            HStack {
                Button("Deny") {
                    viewModel.denyPendingRequest()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Approve Once") {
                    viewModel.approvePendingRequest()
                }
                .buttonStyle(.borderedProminent)
                .tint(approvalTint(approval))
            }
            .controlSize(.small)
        }
        .padding(density.spacing(.md))
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue)
                .strokeBorder(approvalTint(approval).opacity(0.42), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func approvalRow(icon: String, title: String, detail: String?) -> some View {
        HStack(alignment: .top, spacing: density.spacing(.xs)) {
            Image(systemName: icon)
                .commandlyFont(size: 10, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .commandlyFont(size: 10.5, weight: .medium)
                if let detail, detail.isEmpty == false {
                    Text(detail)
                        .commandlyFont(size: 9)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: density.spacing(.xs)) {
                TextField("Ask Finder about files or propose an action…", text: $viewModel.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 12)
                    .lineLimit(1 ... 4)
                    .focused($isPromptFocused)
                    .disabled(viewModel.phase != .ready)
                    .onSubmit {
                        viewModel.send()
                    }
                    .onKeyPress(.escape) {
                        viewModel.handleEscape() ? .handled : .ignored
                    }
                    .accessibilityIdentifier("finder-ai-prompt")

                if viewModel.phase == .responding {
                    Button {
                        viewModel.perform(FinderAIActionID.stopGeneration)
                    } label: {
                        Image(systemName: "stop.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Stop Finder AI")
                } else {
                    Button {
                        viewModel.send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.canSend == false)
                    .accessibilityLabel("Send to Finder AI")
                }
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: CornerRadius.md.rawValue))

            HStack {
                Text(viewModel.composerHint)
                    .commandlyFont(size: 8.5)
                    .foregroundStyle(
                        viewModel.conversationNeedsReset
                            || viewModel.draftIsTooLarge
                            || viewModel.draftWouldExceedConversationLimit
                            ? Color.orange
                            : Color.secondary.opacity(0.65)
                    )
                Spacer()
                if let providerName = viewModel.approvalProviderName {
                    Text("Prompt + tool data → \(providerName)")
                        .commandlyFont(size: 8.5)
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .lineLimit(1)
                        .accessibilityLabel(
                            "Prompts and tool results are sent to \(providerName)"
                        )
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .background(LauncherPalette.chrome)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        let target: AnyHashable? = if viewModel.pendingApproval != nil {
            "finder-ai-approval"
        } else if viewModel.phase == .responding {
            "finder-ai-thinking"
        } else {
            viewModel.entries.last?.id
        }
        guard let target else { return }
        withAnimation(.easeOut(duration: MotionDuration.fast.rawValue)) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func approvalTitle(_ request: FinderAIToolApprovalRequest) -> String {
        switch request {
        case .textRead: "Allow file contents to be read?"
        case .mutation(_, let plan):
            plan.risk == .destructive ? "Move these items to Trash?" : "Approve Finder changes?"
        }
    }

    private func approvalSystemImage(_ request: FinderAIToolApprovalRequest) -> String {
        switch request {
        case .textRead: "doc.text.magnifyingglass"
        case .mutation(_, let plan):
            plan.risk == .destructive ? "trash.fill" : "folder.badge.gearshape"
        }
    }

    private func approvalTint(_ request: FinderAIToolApprovalRequest) -> Color {
        switch request {
        case .textRead: .orange
        case .mutation(_, let plan): plan.risk == .destructive ? .red : .orange
        }
    }

    private func mutationIcon(_ kind: FinderAIMutationPreviewKind) -> String {
        switch kind {
        case .createFolder: "folder.badge.plus"
        case .rename: "pencil"
        case .duplicate: "plus.square.on.square"
        case .copy: "doc.on.doc"
        case .move: "folder"
        case .trash: "trash"
        }
    }

    private func mutationTitle(_ operation: FinderAIMutationPreview) -> String {
        let sources = operation.sourceNames.joined(separator: ", ")
        return switch operation.kind {
        case .createFolder: "Create \(operation.resultingNames.joined(separator: ", "))"
        case .rename: "Rename \(sources)"
        case .duplicate: "Duplicate \(sources)"
        case .copy: "Copy \(sources)"
        case .move: "Move \(sources)"
        case .trash: "Move \(sources) to Trash"
        }
    }

    private func mutationDetail(_ operation: FinderAIMutationPreview) -> String? {
        let results = operation.resultingNames.joined(separator: ", ")
        let destination = operation.destinationDescription
        if let destination, results.isEmpty == false {
            return "\(destination) · Result: \(results)"
        }
        return destination ?? (results.isEmpty ? nil : "Result: \(results)")
    }

    private func warningTitle(_ warning: FinderAIPlanWarning) -> String {
        switch warning {
        case .affectsDirectoryContents: "Includes directory contents"
        case .affectsPackage: "Includes an app or package"
        case .affectsSymbolicLink: "Includes a symbolic link"
        case .changesFilenameExtension: "Changes a filename extension"
        case .batchIsNotAtomic: "Batch may partially complete"
        case .collisionRenamed: "A collision changes the resulting name"
        }
    }
}
