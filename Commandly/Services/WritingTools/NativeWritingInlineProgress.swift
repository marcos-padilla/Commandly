import AppKit
import Infrastructure

@MainActor
protocol WritingInlineProgressPresenting: AnyObject {
    func run(text: String, checker: any WritingChecking, deadline: TimeInterval,
             originName: String?) -> Result<WritingCheckReport, WritingCheckError>
}

/// The Services selector is synchronous. A short native modal loop keeps events and Cancel alive
/// while NSSpellChecker works in the background; no semaphore, sleep, or synchronous checking occurs.
@MainActor
final class NativeWritingInlineProgress: NSObject, WritingInlineProgressPresenting {
    private let now: () -> TimeInterval
    private var operation: WritingInlineOperation?
    private var modalStarted = false
    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func run(text: String, checker: any WritingChecking, deadline: TimeInterval,
             originName: String?) -> Result<WritingCheckReport, WritingCheckError> {
        guard NSApp.modalWindow == nil, operation == nil else { return .failure(.unavailable) }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 130),
            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Quick Fix"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.startAnimation(nil)
        let title = NSTextField(labelWithString: "Checking spelling and grammar…")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: "Local correction for \(originName ?? "your editor"). Escape cancels.")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelRequest))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        let row = NSStackView(views: [indicator, title])
        row.orientation = .horizontal; row.spacing = 10
        let stack = NSStackView(views: [row, detail, cancel])
        stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        if let content = panel.contentView {
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 15),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -12)
            ])
        }
        if let target = WindowPresentationTargetResolver.activeTarget() {
            panel.setFrameOrigin(NSPoint(x: target.visibleFrame.midX - panel.frame.width / 2,
                y: target.visibleFrame.midY - panel.frame.height / 2))
        } else { panel.center() }
        let operation = WritingInlineOperation(deadline: deadline, now: now) { [weak self] in
            guard self?.modalStarted == true else { return }
            NSApp.stopModal()
        }
        self.operation = operation
        let timer = Timer(timeInterval: max(0.001, deadline - now()), repeats: false) { [weak operation] _ in
            MainActor.assumeIsolated { operation?.timeOut() }
        }
        RunLoop.main.add(timer, forMode: .modalPanel)
        let request = checker.check(text: text, language: nil) { [weak operation] result in operation?.receive(result) }
        defer {
            request.cancel(); timer.invalidate(); indicator.stopAnimation(nil)
            modalStarted = false; self.operation = nil; panel.orderOut(nil); panel.close()
        }
        if operation.outcome == nil {
            modalStarted = true
            NSApp.activate()
            // runModal centers a window that is not already visible. Preserve the chosen screen.
            panel.orderFront(nil)
            _ = NSApp.runModal(for: panel)
        }
        return operation.outcome ?? .failure(.cancelled)
    }

    @objc private func cancelRequest() { operation?.cancel() }
}
