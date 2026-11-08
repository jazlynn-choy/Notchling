import Foundation
import IOKit.ps
import ServiceManagement

/// Battery level and charging state from IOKit's power-source API.
public struct IOKitPowerProvider: PowerProviding {
    public init() {}

    public func read() -> PowerStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            if let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
               let status = Self.status(from: description) {
                return status
            }
        }
        return nil
    }

    /// Public for tests: the IOKit dictionary → `PowerStatus` conversion.
    public static func status(from description: [String: Any]) -> PowerStatus? {
        guard let current = description[kIOPSCurrentCapacityKey] as? Int,
              let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        let level = Int((Double(current) / Double(max) * 100).rounded())
        let charging = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return PowerStatus(level: min(100, Swift.max(0, level)), isCharging: charging)
    }
}

/// "Open at login" via `SMAppService`.
public struct MainAppLoginItem: LoginItemManaging {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
