import Foundation
import IOKit
import IOKit.ps
import SMCBridge
public enum PowerError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public enum Battery {
    public static func snapshot() throws -> Status {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { throw PowerError.message("未找到内置电池") }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let values = props?.takeRetainedValue() as? [String: Any],
              let connected = values["ExternalConnected"] as? Bool else {
            throw PowerError.message("无法读取适配器物理连接状态")
        }
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            var result = Status()
            result.percent = min(100, max(0, current * 100 / maximum))
            result.connected = connected
            result.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            result.source = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue ? "外接电源" : "内置电池"
            return result
        }
        throw PowerError.message("无法读取电池电量")
    }
}
public final class Adapter {
    private var key: String?
    private var disabled: UInt8 = 1
    public init() throws {
        #if !arch(arm64)
        throw PowerError.message("仅支持 Apple Silicon MacBook")
        #else
        guard st_smc_open() == 0 else { throw PowerError.message("无法打开 AppleSMC") }
        for (candidate, value) in [("CH0I", UInt8(1)), ("CH0J", UInt8(1)), ("CHIE", UInt8(8))] {
            var byte: UInt8 = 0
            if st_smc_read(candidate, &byte) == 0 && (byte == 0 || byte == value) { key = candidate; disabled = value; break }
        }
        guard key != nil else { throw PowerError.message("此机型或固件不支持适配器控制") }
        #endif
    }
    public func set(enabled: Bool) throws {
        guard let key else { throw PowerError.message("适配器控制不可用") }
        let code = st_smc_write(key, enabled ? 0 : disabled)
        guard code == 0 else { throw PowerError.message("供电切换失败（SMC \(code)）") }
        var readback: UInt8 = 0
        guard st_smc_read(key, &readback) == 0, readback == (enabled ? 0 : disabled) else {
            throw PowerError.message("供电控制写入未通过回读验证")
        }
    }
}
