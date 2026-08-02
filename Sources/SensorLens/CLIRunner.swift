import Foundation

enum CLIError: LocalizedError {
    case binaryNotFound
    case launchFailed(detail: String)
    case runFailed(summary: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "sensor-lens CLI not found. Reinstall SensorLens.app (the CLI ships bundled), or install sensor-lens on your PATH."
        case .launchFailed:
            return "Couldn't start the sensor-lens CLI. Reinstall the app if this keeps happening."
        case .runFailed(let summary, _):
            return summary
        }
    }

    var failureReason: String? {
        switch self {
        case .binaryNotFound: return nil
        case .launchFailed(let d): return d.isEmpty ? nil : d
        case .runFailed(_, let d): return d.isEmpty ? nil : d
        }
    }

    /// Translate a CLI failure into a short, actionable summary. Pure (testable);
    /// the raw stderr stays available separately as the detail.
    static func summarize(exitCode: Int32, crashed: Bool, stderr: String) -> String {
        let s = stderr.lowercased()
        if crashed {
            return "The sensor-lens CLI stopped unexpectedly. Try Refresh; if it keeps happening, reinstall the app."
        }
        if s.contains("no switchbot credentials") || s.contains("missing token") {
            return "No SwitchBot credentials yet. Open Settings and paste the token and secret from the SwitchBot app."
        }
        // Over the daily quota the API answers "Unauthorized", the same as a bad
        // token — so the two possibilities have to be named together.
        if s.contains("unauthorized") {
            return "SwitchBot refused the request. Either the token is wrong or the account's daily API limit is spent — Settings shows today's usage."
        }
        if s.contains("already running") {
            return "Another sensor-lens collector is already running, so this app is only displaying its data."
        }
        if s.contains("permission denied") || s.contains("operation not permitted") {
            return "The CLI was denied access it needed. Reinstall the app if this keeps happening."
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "The sensor-lens CLI exited with an error (code \(exitCode))."
        }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return "The sensor-lens CLI reported: \(firstLine)"
    }
}

/// CLIRunner locates and invokes the sensor-lens CLI, decoding its --json output.
/// The CLI owns the credentials, the API calls and the database; this app is a
/// thin front end over it.
enum CLIRunner {
    /// Resolve the CLI binary. The **bundled** copy in the .app's Resources is the
    /// trust anchor: it ships Developer-ID signed + notarized, so it can't be
    /// swapped without invalidating the signature. In a release build it comes
    /// first and no environment variable can redirect execution. In DEBUG builds
    /// the `$SENSOR_LENS_BIN` override and the local dev path are honored.
    ///
    /// This matters more here than in a purely local tool: the binary being run
    /// holds an API token that can control every device on the account.
    static func findBinary() -> String? {
        var allowEnvOverride = false
        var devPaths: [String] = []
        #if DEBUG
        allowEnvOverride = true
        devPaths = [NSHomeDirectory() + "/works/nlink-jp/_wip/sensor-lens/dist/sensor-lens"]
        #endif
        return resolveBinary(
            env: ProcessInfo.processInfo.environment,
            allowEnvOverride: allowEnvOverride,
            bundled: Bundle.main.resourceURL?.appendingPathComponent("sensor-lens").path,
            devPaths: devPaths,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    /// Pure resolution logic (injectable for tests). Order:
    ///   [env, only if allowEnvOverride] → bundled → /usr/local, /opt/homebrew → [devPaths]
    static func resolveBinary(
        env: [String: String],
        allowEnvOverride: Bool,
        bundled: String?,
        devPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        var order: [String] = []
        if allowEnvOverride, let p = env["SENSOR_LENS_BIN"] {
            order.append(p)
        }
        if let bundled {
            order.append(bundled)
        }
        order += ["/usr/local/bin/sensor-lens", "/opt/homebrew/bin/sensor-lens"]
        order += devPaths
        return order.first(where: isExecutable)
    }

    @discardableResult
    static func run(_ args: [String]) throws -> Data {
        guard let bin = findBinary() else { throw CLIError.binaryNotFound }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw CLIError.launchFailed(detail: error.localizedDescription)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let crashed = proc.terminationReason == .uncaughtSignal
            throw CLIError.runFailed(
                summary: CLIError.summarize(exitCode: proc.terminationStatus, crashed: crashed, stderr: stderr),
                detail: stderr
            )
        }
        return data
    }

    // MARK: - Typed queries

    /// The collecting tick.
    ///
    /// `--if-stale` polls only when the stored readings have aged past the
    /// interval, so this app can run its timer without knowing whether a daemon
    /// is also collecting: if one is, the data is fresh and this costs no API
    /// calls. That is the whole coordination mechanism — do not add a check on
    /// `daemonLoaded` here.
    static func tick() throws -> [DeviceReading] {
        try decode([DeviceReading].self, from: run(["now", "--if-stale", "--json"]))
    }

    /// Force a poll now, whatever the stored data's age (the Refresh button).
    static func pollNow() throws -> [DeviceReading] {
        try decode([DeviceReading].self, from: run(["now", "--json"]))
    }

    /// The last stored values, without touching the API.
    static func stored() throws -> [DeviceReading] {
        try decode([DeviceReading].self, from: run(["now", "--stored", "--json"]))
    }

    static func status() throws -> Status {
        try decode(Status.self, from: run(["status", "--json"]))
    }

    static func devices() throws -> [Device] {
        try decode([Device].self, from: run(["devices", "--json"]))
    }

    static func refreshDevices() throws -> [Device] {
        try decode([Device].self, from: run(["devices", "--refresh", "--json"]))
    }

    static func history(device: String, metric: String, since: String) throws -> [Reading] {
        try decode([Reading].self, from: run(
            ["history", "--device", device, "--metric", metric, "--since", since, "--json"]))
    }

    /// Downsampled history. Deliberately a separate call rather than an optional
    /// argument to `history`: `--bucket` makes the CLI emit buckets, a different
    /// shape entirely, so the two cannot share a return type.
    ///
    /// This reads the local database only — no API call, no quota spent.
    static func historyBuckets(device: String, metric: String, since: String, bucket: String) throws -> [Bucket] {
        try decode([Bucket].self, from: run(
            ["history", "--device", device, "--metric", metric,
             "--since", since, "--bucket", bucket, "--json"]))
    }

    static func gaps(since: String) throws -> [Gap] {
        try decode([Gap].self, from: run(["gaps", "--since", since, "--json"]))
    }

    static func report(since: String) throws -> [Summary] {
        try decode([Summary].self, from: run(["report", "--since", since, "--json"]))
    }

    static func install() throws { _ = try run(["install"]) }
    static func uninstall() throws { _ = try run(["uninstall"]) }

    /// Decode, treating "nothing" as an empty list rather than a failure.
    ///
    /// Go marshals a nil slice as `null`, so a query that legitimately found
    /// nothing — no gaps, no devices yet — arrives as `null`, and "no readings
    /// yet" is a normal state on a fresh install, not an error to show the user.
    /// For a non-list result (Status) the substitution simply fails to decode,
    /// which is the right outcome: an empty status is a real problem.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let payload = (trimmed == "null" || trimmed.isEmpty) ? Data("[]".utf8) : data
        return try JSONDecoder().decode(type, from: payload)
    }
}
