import Foundation
public enum Phase: String, Codable { case idle, discharging, charging }
public struct Cycle {
    public private(set) var phase: Phase = .idle
    public init() {}
    public var adapterEnabled: Bool { phase != .discharging }
    public mutating func start(percent: Int) { phase = percent < 10 ? .charging : .discharging }
    public mutating func stop() { phase = .idle }
    public mutating func update(percent: Int, connected: Bool) {
        guard phase != .idle else { return }
        if !connected { stop(); return }
        if phase == .discharging && percent < 10 { phase = .charging }
        else if phase == .charging && percent >= 100 { phase = .discharging }
    }
}
public struct Status: Codable {
    public var percent: Int = 0
    public var connected = false
    public var charging = false
    public var source = "未知"
    public var phase: Phase = .idle
    public var supported = false
    public var ownsControl = false
    public var error: String? = nil
    public init() {}
}
