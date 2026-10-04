import XCTest
@testable import PowerCore
final class CycleTests: XCTestCase {
    func testCompleteCycleAndStrictThreshold() {
        var cycle = Cycle()
        cycle.start(percent: 50)
        XCTAssertEqual(cycle.phase, .discharging)
        cycle.update(percent: 10, connected: true)
        XCTAssertEqual(cycle.phase, .discharging)
        cycle.update(percent: 9, connected: true)
        XCTAssertEqual(cycle.phase, .charging)
        cycle.update(percent: 99, connected: true)
        XCTAssertEqual(cycle.phase, .charging)
        cycle.update(percent: 100, connected: true)
        XCTAssertEqual(cycle.phase, .discharging)
    }
    func testLowStartAndUnplugDoesNotRestart() {
        var cycle = Cycle()
        cycle.start(percent: 9)
        XCTAssertEqual(cycle.phase, .charging)
        cycle.update(percent: 30, connected: false)
        XCTAssertEqual(cycle.phase, .idle)
        cycle.update(percent: 30, connected: true)
        XCTAssertEqual(cycle.phase, .idle)
    }
    func testStopRestoresAdapterIntent() {
        var cycle = Cycle()
        cycle.start(percent: 100)
        XCTAssertFalse(cycle.adapterEnabled)
        cycle.stop()
        XCTAssertTrue(cycle.adapterEnabled)
    }
}
