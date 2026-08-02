import UserNotifications
import XCTest
@testable import SensorLens

final class NotificationsTests: XCTestCase {
    func testMapsEveryAuthorizationStatus() {
        XCTAssertEqual(Notifications.map(.authorized), .allowed)
        XCTAssertEqual(Notifications.map(.denied), .denied)
        XCTAssertEqual(Notifications.map(.notDetermined), .notDetermined)
    }

    /// Provisional delivers, quietly. Treating it as anything else would warn
    /// the user that nothing will arrive while notifications were in fact
    /// arriving.
    func testProvisionalCountsAsAllowed() {
        XCTAssertEqual(Notifications.map(.provisional), .allowed)
        XCTAssertTrue(Notifications.map(.provisional).canDeliver)
    }

    /// "Not asked yet" is not "refused". The first is fixed by asking, the
    /// second by sending the user to System Settings, and telling them the
    /// wrong one wastes their time.
    func testNotDeterminedIsNotDenied() {
        XCTAssertNotEqual(Notifications.map(.notDetermined), .denied)
        XCTAssertFalse(Notifications.map(.notDetermined).canDeliver)
        XCTAssertFalse(Notifications.map(.denied).canDeliver)
    }
}
