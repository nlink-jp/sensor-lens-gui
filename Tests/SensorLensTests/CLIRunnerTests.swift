import XCTest
@testable import SensorLens

final class CLIRunnerTests: XCTestCase {
    /// The bundled, signed CLI is the trust anchor. It holds a token that can
    /// control every device on the account, so a release build must not let an
    /// environment variable point the app at a different binary.
    func testReleaseBuildIgnoresTheEnvironmentOverride() {
        let got = CLIRunner.resolveBinary(
            env: ["SENSOR_LENS_BIN": "/tmp/attacker/sensor-lens"],
            allowEnvOverride: false,
            bundled: "/Applications/SensorLens.app/Contents/Resources/sensor-lens",
            devPaths: [],
            isExecutable: { _ in true }
        )
        XCTAssertEqual(got, "/Applications/SensorLens.app/Contents/Resources/sensor-lens")
    }

    func testDebugBuildHonoursTheEnvironmentOverride() {
        let got = CLIRunner.resolveBinary(
            env: ["SENSOR_LENS_BIN": "/tmp/dev/sensor-lens"],
            allowEnvOverride: true,
            bundled: "/Applications/SensorLens.app/Contents/Resources/sensor-lens",
            devPaths: [],
            isExecutable: { _ in true }
        )
        XCTAssertEqual(got, "/tmp/dev/sensor-lens")
    }

    func testFallsBackToAnInstalledCLI() {
        let got = CLIRunner.resolveBinary(
            env: [:],
            allowEnvOverride: false,
            bundled: "/Applications/SensorLens.app/Contents/Resources/sensor-lens",
            devPaths: [],
            isExecutable: { $0 == "/opt/homebrew/bin/sensor-lens" }
        )
        XCTAssertEqual(got, "/opt/homebrew/bin/sensor-lens")
    }

    func testNoBinaryAnywhere() {
        XCTAssertNil(CLIRunner.resolveBinary(
            env: [:], allowEnvOverride: false, bundled: nil, devPaths: [],
            isExecutable: { _ in false }))
    }

    // MARK: - Error messages

    /// Over quota the API answers "Unauthorized" — the same thing a wrong token
    /// produces — so the message has to name both possibilities rather than
    /// sending the user to re-check a token that is fine.
    func testUnauthorizedMentionsBothCauses() {
        let msg = CLIError.summarize(exitCode: 1, crashed: false,
                                     stderr: "sensor-lens: switchbot: HTTP 401: Unauthorized")
        XCTAssertTrue(msg.contains("token"), msg)
        XCTAssertTrue(msg.lowercased().contains("daily"), msg)
    }

    func testMissingCredentialsPointsAtSettings() {
        let msg = CLIError.summarize(exitCode: 1, crashed: false,
                                     stderr: "sensor-lens: no SwitchBot credentials: set them in ...")
        XCTAssertTrue(msg.contains("Settings"), msg)
    }

    func testAnotherCollectorIsExplainedNotAlarming() {
        let msg = CLIError.summarize(exitCode: 1, crashed: false,
                                     stderr: "sensor-lens: another sensor-lens collector is already running")
        XCTAssertTrue(msg.contains("displaying"), msg)
    }

    func testCrashIsReportedAsSuch() {
        let msg = CLIError.summarize(exitCode: -1, crashed: true, stderr: "")
        XCTAssertTrue(msg.contains("stopped unexpectedly"), msg)
    }

    func testEmptyStderrStillSaysSomething() {
        let msg = CLIError.summarize(exitCode: 2, crashed: false, stderr: "")
        XCTAssertTrue(msg.contains("2"), msg)
    }

    // MARK: - Decoding

    /// Go marshals a nil slice as `null`, so "found nothing" must decode as an
    /// empty list rather than throwing — no gaps is the good outcome.
    func testNullDecodesAsEmptyList() throws {
        let gaps = try CLIRunner.decode([Gap].self, from: Data("null".utf8))
        XCTAssertTrue(gaps.isEmpty)
    }

    func testDecodesRealNowOutput() throws {
        let json = """
        [{"device_id":"B0E9FE548B10","name":"CO2センサー (Room 1)","device_type":"MeterPro(CO2)",
          "metrics":{"battery_pct":100,"co2_ppm":1094,"humidity_pct":47,"temperature_c":27.5},
          "ts":1785673750,"stale":false}]
        """
        let readings = try CLIRunner.decode([DeviceReading].self, from: Data(json.utf8))

        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings[0].name, "CO2センサー (Room 1)")
        XCTAssertEqual(readings[0].metrics["co2_ppm"], 1094)
        XCTAssertFalse(readings[0].stale)
    }

    func testDecodesRealStatusOutput() throws {
        let json = """
        {"cli_version":"v0.1.0","db_path":"/db","config_path":"/cfg","daemon_kind":"launchd",
         "daemon_loaded":true,"daemon_installed":true,"interval_seconds":300,"devices":30,
         "collected":15,"readings":15754,"last_reading_ts":1785673495,"stale":false,
         "collecting":true,"calls_today":141,"daily_budget":8000,
         "projected_calls_per_day":4321,"has_credentials":true}
        """
        let status = try CLIRunner.decode(Status.self, from: Data(json.utf8))

        XCTAssertTrue(status.collecting)
        XCTAssertEqual(status.collected, 15)
        XCTAssertEqual(status.projectedCallsPerDay, 4321)
    }
}
