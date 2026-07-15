import Foundation
import Testing
@testable import SecurityKit

struct SecurityKitTests {
    @Test func permissionCheckerDefaultsToNotDetermined() async {
        let checker = InMemoryPermissionChecker()
        let state = await checker.state(for: .accessibility)
        #expect(state == .notDetermined)
    }

    @Test func permissionCheckerReturnsConfiguredState() async {
        let checker = InMemoryPermissionChecker(states: [.notifications: .authorized])
        let state = await checker.state(for: .notifications)
        #expect(state == .authorized)
    }

    @Test func sensitiveValueIsRedactedInDescription() {
        let value = SensitiveValue("super-secret")
        #expect(value.description == "<redacted>")
        #expect(value.debugDescription == "<redacted>")
        #expect(value.customMirror.children.first?.value as? String == "<redacted>")
        #expect(value.reveal() == "super-secret")
    }

    @Test func inMemorySecureStoreRoundTripsUpdatesAndDeletes() async throws {
        let store = InMemorySecureStore()
        let key = SecureStoreKey(rawValue: "ai.provider.test")
        let original = Data("first-value".utf8)
        let replacement = Data("replacement-value".utf8)

        #expect(try await store.read(key) == nil)

        try await store.write(key, value: original)
        #expect(try await store.read(key) == original)

        try await store.write(key, value: replacement)
        #expect(try await store.read(key) == replacement)

        try await store.delete(key)
        #expect(try await store.read(key) == nil)

        // Deletion is intentionally idempotent.
        try await store.delete(key)
        #expect(try await store.read(key) == nil)
    }

    @Test func inMemorySecureStoreSerializesConcurrentAccess() async throws {
        let store = InMemorySecureStore()
        let count = 32

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<count {
                group.addTask {
                    let key = SecureStoreKey(rawValue: "concurrent.\(index)")
                    try await store.write(key, value: Data([UInt8(index)]))
                }
            }
            try await group.waitForAll()
        }

        for index in 0..<count {
            let key = SecureStoreKey(rawValue: "concurrent.\(index)")
            #expect(try await store.read(key) == Data([UInt8(index)]))
        }
    }

    @Test func inMemorySecureStoreRejectsInvalidKeysWithoutSecretPayloads() async {
        let store = InMemorySecureStore()
        let invalidKey = SecureStoreKey(rawValue: "  \n")
        let secret = "must-not-appear"

        do {
            try await store.write(invalidKey, value: Data(secret.utf8))
            Issue.record("Expected an invalid secure-store key to fail")
        } catch let error as SecureStoreError {
            #expect(error == .invalidKey)
            #expect(error.localizedDescription.contains(secret) == false)
            #expect(error.localizedDescription.contains(invalidKey.rawValue) == false)
        } catch {
            Issue.record("Unexpected secure-store error type")
        }
    }

    @Test func secureStoreErrorsExposeOnlySanitizedDescriptions() {
        let marker = "private-marker"
        let errors: [SecureStoreError] = [
            .invalidKey,
            .invalidConfiguration,
            .accessDenied,
            .interactionNotAllowed,
            .unavailable,
            .invalidData,
            .operationFailed,
        ]

        #expect(errors.allSatisfy { $0.localizedDescription.contains(marker) == false })
        #expect(errors.allSatisfy { $0.localizedDescription.isEmpty == false })
    }

    @Test func inMemoryPermissionServiceGrantsOnRequest() async {
        let service = InMemoryPermissionService()
        #expect(await service.state(for: .calendar) == .notDetermined)
        let result = await service.request(.calendar)
        #expect(result == .authorized)
        #expect(await service.state(for: .calendar) == .authorized)
    }

    @Test func inMemoryPermissionServiceKeepsDenied() async {
        let service = InMemoryPermissionService(states: [.contacts: .denied])
        let result = await service.request(.contacts)
        #expect(result == .denied)
    }
}
