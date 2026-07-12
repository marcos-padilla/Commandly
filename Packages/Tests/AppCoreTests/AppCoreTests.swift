import Foundation
import Testing
@testable import AppCore

struct AppCoreTests {
    @Test func fixedUUIDProviderReturnsDeterministicValue() throws {
        let uuid = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let provider = FixedUUIDProvider(uuid: uuid)
        #expect(provider.uuid() == uuid)
        #expect(provider.uuid() == provider.uuid())
    }

    @Test func fixedDateProviderReturnsDeterministicValue() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = FixedDateProvider(date: date)
        #expect(provider.now() == date)
    }

    @Test func applicationMetadataEquality() {
        let metadata = ApplicationMetadata(
            name: "Commandly",
            version: "1.0",
            build: "1",
            bundleIdentifier: "com.businessmate360.Commandly",
            environment: .testing
        )
        let copy = ApplicationMetadata(
            name: "Commandly",
            version: "1.0",
            build: "1",
            bundleIdentifier: "com.businessmate360.Commandly",
            environment: .testing
        )
        #expect(metadata == copy)
    }

    @Test func continuousClockReturnsInstant() {
        let clock = ContinuousSystemClock()
        let first = clock.monotonicTime()
        let second = clock.monotonicTime()
        #expect(second >= first)
    }
}
