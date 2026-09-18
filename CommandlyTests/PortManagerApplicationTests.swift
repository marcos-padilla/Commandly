import CommandKit
import Testing
@testable import Commandly

@MainActor
struct PortManagerApplicationTests {
    @Test func parserReadsStructuredIPv4AndIPv6Listeners() {
        let output = """
        p42
        cnode
        n*:3000
        p88
        cpython3
        n[::1]:8000
        """

        #expect(
            NativePortManager.parse(output, transport: .tcp) == [
                ListeningPort(
                    transport: .tcp,
                    port: 3000,
                    processIdentifier: 42,
                    processName: "node",
                    address: "*"
                ),
                ListeningPort(
                    transport: .tcp,
                    port: 8000,
                    processIdentifier: 88,
                    processName: "python3",
                    address: "[::1]"
                )
            ]
        )
    }

    @Test func applicationPresentsListenerSession() throws {
        let listener = ListeningPort(transport: .tcp, port: 3000, processIdentifier: 42, processName: "node", address: "*")
        let service = FakePortManager(listeners: [listener])
        let application = PortManagerApplication(service: service)

        let launch = application.launch(in: makeContext())
        guard case .present(let session) = launch else {
            Issue.record("Expected Port Manager to present a session")
            return
        }
        let model = try #require(session.model(as: PortManagerViewModel.self))
        #expect(application.definition.id == PortManagerApplicationID.command)
        #expect(model.footerActions.first?.id == PortManagerActionID.terminate)
    }

    @Test func applicationOwnsTypedInspectAndKillPortTools() throws {
        let application = PortManagerApplication(service: FakePortManager())
        let inspectTool = try #require(
            application.toolDefinitions.first {
                $0.id == PortManagerApplicationID.inspectTool
            }
        )
        let killTool = try #require(
            application.toolDefinitions.first {
                $0.id == PortManagerApplicationID.killPortTool
            }
        )
        let portArgument = try #require(killTool.commandManifest?.arguments.first)
        let command = try #require(application.commandDefinitions.first)

        #expect(application.toolDefinitions.count == 2)
        #expect(inspectTool.kind == .tool)
        #expect(inspectTool.parentID == PortManagerApplicationID.command)
        #expect(killTool.kind == .tool)
        #expect(killTool.parentID == PortManagerApplicationID.command)
        #expect(killTool.commandManifest?.mode == .action)
        #expect(portArgument.name == PortManagerApplicationID.portArgument)
        #expect(portArgument.valueType == .integer)
        #expect(portArgument.isRequired == false)
        #expect(command.toolID == PortManagerApplicationID.killPortTool)
        #expect(command.syntax == "kill port <number>")
    }

    @Test(arguments: [
        ("kill port 3000", 3000),
        ("  KILL   PoRt  8080 \n", 8080),
        ("stop port 65535", 65535),
    ])
    func killPortCommandNormalizesValidInput(
        query: String,
        expectedPort: Int
    ) throws {
        let application = PortManagerApplication(service: FakePortManager())
        let command = try #require(application.commandDefinitions.first)
        let match = try #require(command.match(query))

        #expect(match.reference.commandID == PortManagerApplicationID.killPortTool)
        #expect(
            match.reference.arguments[PortManagerApplicationID.portArgument]
                == .integer(expectedPort)
        )
        #expect(match.title == "Kill Port \(expectedPort)")
    }

    @Test(arguments: [
        "",
        "kill port",
        "kill port 0",
        "kill port -1",
        "kill port 65536",
        "kill port 3000 now",
        "kill port 3000; rm -rf /",
        "kill port $(whoami)",
        "kill ports 3000",
        "restart port 3000",
    ])
    func killPortCommandRejectsInvalidOrUnboundedInput(query: String) throws {
        let application = PortManagerApplication(service: FakePortManager())
        let command = try #require(application.commandDefinitions.first)

        #expect(command.match(query) == nil)
    }

    @Test func killPortToolPreloadsMatchingListenerButWaitsForConfirmation() async throws {
        let listener = ListeningPort(
            transport: .tcp,
            port: 3000,
            processIdentifier: 42,
            processName: "node",
            address: "*"
        )
        let service = FakePortManager(listeners: [listener])
        let application = PortManagerApplication(service: service)
        let arguments = CommandArguments([
            PortManagerApplicationID.portArgument: .integer(3000)
        ])

        let launch = application.launch(
            toolID: PortManagerApplicationID.killPortTool,
            arguments: arguments,
            in: makeContext()
        )
        guard case .present(let session) = launch else {
            Issue.record("Expected Kill Port to present Port Manager")
            return
        }
        let model = try #require(session.model(as: PortManagerViewModel.self))

        #expect(model.query == "3000")
        #expect(model.pendingTermination == nil)
        #expect(await service.terminated.isEmpty)

        model.start()
        try await waitUntil { model.pendingTermination == listener }

        #expect(model.selectedListener == listener)
        #expect(await service.terminated.isEmpty)

        model.perform(PortManagerActionID.confirm)
        try await waitUntil { await service.terminated == [listener] }
    }

    @Test func selectingAndConfirmingStopsTheSelectedListener() async throws {
        let listener = ListeningPort(transport: .udp, port: 5353, processIdentifier: 99, processName: "service", address: "*")
        let service = FakePortManager(listeners: [listener])
        let model = PortManagerViewModel(service: service, onGoBack: {})
        model.start()
        try await waitUntil { model.selectedListener == listener }
        model.perform(PortManagerActionID.terminate)
        #expect(model.pendingTermination == listener)
        model.perform(PortManagerActionID.confirm)
        try await waitUntil { await service.terminated == [listener] }
    }

    private func waitUntil(_ condition: @escaping @MainActor () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition did not become true")
    }

    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )
    }
}

private actor FakePortManager: PortManaging {
    let listeners: [ListeningPort]
    private(set) var terminated: [ListeningPort] = []

    init(listeners: [ListeningPort] = []) { self.listeners = listeners }
    func listeningPorts() async throws -> [ListeningPort] { listeners }
    func terminate(listener: ListeningPort) async throws { terminated.append(listener) }
}
