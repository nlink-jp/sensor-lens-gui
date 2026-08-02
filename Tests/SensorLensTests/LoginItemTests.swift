import ServiceManagement
import XCTest
@testable import SensorLens

final class LoginItemTests: XCTestCase {
    func testMapsEveryStatusTheSystemCanReport() {
        XCTAssertEqual(LoginItem.state(from: .enabled), .enabled)
        XCTAssertEqual(LoginItem.state(from: .notRegistered), .disabled)
        XCTAssertEqual(LoginItem.state(from: .notFound), .unavailable)
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
        let known: [LoginItem.State] = [.enabled, .disabled, .requiresApproval, .unavailable]
        XCTAssertTrue(known.contains(LoginItem.current))
    }
}
