import Darwin
import Foundation
import Infrastructure
import SystemCompanionKit

/// Default application launch shows setup; only the signed LaunchAgent selects the headless --service mode.
@main
enum SystemCompanionMain {
    static func main() async {
        do {
            switch try CompanionLaunchMode.resolve(arguments: Array(CommandLine.arguments.dropFirst())) {
            case .setup: SystemCompanionSetupApplication.run()
            case .service: try await SystemCompanionRuntime().run()
            }
        }
        catch { exit(EX_CONFIG) }
    }
}

private actor SystemCompanionRuntime {
    private var listener: NSXPCListener?
    private var delegate: CompanionXPCServerDelegate?
    private var signals: [any DispatchSourceSignal] = []
    func run() async throws {
        let policy = try CompanionSigningPolicy()
        _ = try await NativeCompanionSetupValidator().validate()
        let userSession = try CompanionUserSession.current()
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              CompanionWireCodec.validBuild(build) else { throw CompanionError.invalidConfiguration }
        let sessions = CompanionServerSessions()
        let delegate = CompanionXPCServerDelegate(policy: policy, userSession: userSession, build: build, sessions: sessions,
            windowLayoutFactory: CompanionWindowLayoutReleaseGate.reviewed ? .native : nil,
            appMenuFactory: CompanionAppMenuReleaseGate.reviewed ? .native : nil,
            keyboardTriggerFactory: CompanionKeyboardTriggerReleaseGate.reviewed ? .native : nil)
        let listener = NSXPCListener(machServiceName: CompanionIdentity.machService)
        // The delegate applies the one peer requirement to each accepted connection before activation.
        listener.delegate = delegate
        self.listener = listener; self.delegate = delegate
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global(qos: .utility))
            source.setEventHandler { continuation.yield(); continuation.finish() }
            source.activate(); signals.append(source)
        }
        listener.activate()
        // Wait for an actual termination signal, rather than polling or using a fabricated sleep.
        for await _ in events { break }
        listener.invalidate()
        await sessions.invalidateAll()
        for source in signals { source.cancel() }
        signals.removeAll(); self.listener = nil; self.delegate = nil
    }
}
