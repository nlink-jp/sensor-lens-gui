import ServiceManagement
import XCTest
@testable import SensorLens

final class LoginItemTests: XCTestCase {
    func testMapsEveryStatusTheSystemCanReport() {
        XCTAssertEqual(LoginItem.state(from: .enabled), .enabled)
        XCTAssertEqual(LoginItem.state(from: .notRegistered), .notEnabled)
    }

    /// Regression: `.notFound` was treated as "this copy cannot be registered",
    /// and the switch was disabled on the strength of it. macOS returns it for
    /// an app that has simply never registered — which is every app the first
    /// time — so the one attempt that would have fixed it was the one the UI
    /// refused to allow.
    func testNotFoundIsNotAnImpossibility() {
        XCTAssertEqual(LoginItem.state(from: .notFound), .notEnabled)
    }

    /// Registered-but-blocked must not collapse into "enabled". The switch would
    /// read as on while nothing actually happens at login, and the user would
    /// have no way to find out why the app never appeared.
    func testAwaitingApprovalIsItsOwnState() {
        XCTAssertEqual(LoginItem.state(from: .requiresApproval), .requiresApproval)
        XCTAssertNotEqual(LoginItem.state(from: .requiresApproval), .enabled)
    }

    /// Reading the real status must not throw or hang; whatever this machine
    /// reports, it has to be one of the four the UI knows how to draw.
    func testCurrentStateIsAlwaysRenderable() {
        let known: [LoginItem.State] = [.enabled, .notEnabled, .requiresApproval]
        XCTAssertTrue(known.contains(LoginItem.current))
    }
}
