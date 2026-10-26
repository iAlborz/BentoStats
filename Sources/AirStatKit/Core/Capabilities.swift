import Foundation

/// What this copy of the app can read.
///
/// The Mac App Store copy runs in the App Sandbox, which closes the SMC, the only source
/// of temperatures and fan speeds, and App Review does not grant the exception that would
/// open it. That copy shows macOS's thermal state where they would be; the copy
/// downloaded from outside the store reads them as before.
public enum Capabilities {
    /// Temperatures and fan speeds. False in the App Sandbox, or with
    /// `AIRSTAT_NO_SENSORS=1`, which draws the store's version of the panel outside it.
    public static let readsSensors: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] == nil && environment["AIRSTAT_NO_SENSORS"] != "1"
    }()

    /// Said wherever a temperature or a fan speed would have been.
    public static let noSensorsReason = "macOS does not let App Store apps read temperatures or fan speeds."
}
