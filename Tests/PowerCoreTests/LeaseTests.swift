import XCTest
@testable import PowerCore
final class LeaseTests: XCTestCase {
    func testOwnerOnlyRenewalAndTimeout() {
        var lease = Lease()
        lease.claim(pid: 42, now: 100)
        lease.renew(pid: 99, now: 125)
        XCTAssertTrue(lease.expired(now: 131, processAlive: true))
        lease.renew(pid: 42, now: 132)
        XCTAssertFalse(lease.expired(now: 140, processAlive: true))
        XCTAssertTrue(lease.expired(now: 140, processAlive: false))
    }
    func testSleepDoesNotExpireWhenAwakeClockDoesNotAdvance() {
        var lease = Lease()
        lease.claim(pid: 42, now: 100)
        XCTAssertFalse(lease.expired(now: 100, processAlive: true))
        lease.release()
        XCTAssertFalse(lease.expired(now: 1000, processAlive: false))
    }
}
