import Darwin
import Foundation

/// A transport protocol for a locally listening endpoint.
nonisolated enum ListeningPortTransport: String, CaseIterable, Sendable, Equatable {
    case tcp
    case udp

    var title: String { rawValue.uppercased() }
}

/// One local endpoint currently owned by a process.
nonisolated struct ListeningPort: Identifiable, Sendable, Equatable, Hashable {
    let transport: ListeningPortTransport
    let port: UInt16
    let processIdentifier: Int32
    let processName: String
    let address: String

    var id: String { "\(transport.rawValue):\(port):\(processIdentifier):\(address)" }
}

nonisolated enum PortManagementError: LocalizedError, Sendable, Equatable {
    case inspectionUnavailable
    case listenerNoLongerAvailable
    case terminationDenied

    var errorDescription: String? {
        switch self {
        case .inspectionUnavailable:
            return "Listening ports are unavailable on this Mac."
        case .listenerNoLongerAvailable:
            return "That listener is no longer active. Refresh and try again."
        case .terminationDenied:
            return "macOS did not allow Commandly to stop that process."
        }
    }
}

/// Narrow system boundary for inspecting and explicitly stopping local listeners.
nonisolated protocol PortManaging: Sendable {
    func listeningPorts() async throws -> [ListeningPort]
    func terminate(listener: ListeningPort) async throws
}

/// Runs a fixed, argument-free-from-user-input system command.
nonisolated protocol PortInspectionCommandRunning: Sendable {
    func run(arguments: [String]) throws -> String
}

/// Native adapter that reads `lsof`'s structured output and uses `kill(2)` for an explicit stop.
/// It never interpolates a user query into a command or records returned process metadata.
actor NativePortManager: PortManaging {
    private let commandRunner: any PortInspectionCommandRunning

    init(commandRunner: any PortInspectionCommandRunning = NativePortInspectionCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func listeningPorts() throws -> [ListeningPort] {
        let tcp = try commandRunner.run(arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"])
        let udp = try commandRunner.run(arguments: ["-nP", "-iUDP", "-Fpcn"])
        return Self.parse(tcp, transport: .tcp) + Self.parse(udp, transport: .udp)
    }

    func terminate(listener: ListeningPort) async throws {
        let stillListening = try listeningPorts().contains {
            $0.transport == listener.transport
                && $0.port == listener.port
                && $0.processIdentifier == listener.processIdentifier
        }
        guard stillListening else { throw PortManagementError.listenerNoLongerAvailable }
        guard Darwin.kill(listener.processIdentifier, SIGTERM) == 0 else {
            throw PortManagementError.terminationDenied
        }
    }

    nonisolated static func parse(
        _ output: String,
        transport: ListeningPortTransport
    ) -> [ListeningPort] {
        var result: [ListeningPort] = []
        var processIdentifier: Int32?
        var processName = "Process"

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                processIdentifier = Int32(value)
                processName = "Process"
            case "c":
                processName = value.isEmpty ? "Process" : value
            case "n":
                guard let processIdentifier,
                      let endpoint = endpoint(from: value) else { continue }
                result.append(
                    ListeningPort(
                        transport: transport,
                        port: endpoint.port,
                        processIdentifier: processIdentifier,
                        processName: processName,
                        address: endpoint.address
                    )
                )
            default:
                continue
            }
        }
        return Array(Set(result)).sorted {
            if $0.port != $1.port { return $0.port < $1.port }
            if $0.transport != $1.transport { return $0.transport.rawValue < $1.transport.rawValue }
            return $0.processIdentifier < $1.processIdentifier
        }
    }

    private nonisolated static func endpoint(from value: String) -> (address: String, port: UInt16)? {
        let endpoint = value.split(separator: " ", maxSplits: 1).first.map(String.init) ?? value
        guard let separator = endpoint.lastIndex(of: ":"),
              let port = UInt16(endpoint[endpoint.index(after: separator)...]) else {
            return nil
        }
        return (String(endpoint[..<separator]), port)
    }
}

private struct NativePortInspectionCommandRunner: PortInspectionCommandRunning {
    func run(arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PortManagementError.inspectionUnavailable
        }
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            throw PortManagementError.inspectionUnavailable
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
