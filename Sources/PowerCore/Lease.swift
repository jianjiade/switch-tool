public struct Lease {
    public private(set) var owner: Int32 = 0
    private var lastHeartbeat: Double = 0
    public init() {}
    public mutating func claim(pid: Int32, now: Double) { owner = pid; lastHeartbeat = now }
    public mutating func renew(pid: Int32, now: Double) { if owner == pid { lastHeartbeat = now } }
    public mutating func release() { owner = 0 }
    // The caller supplies mach_absolute_time, which excludes sleep.
    public func expired(now: Double, processAlive: Bool) -> Bool {
        owner != 0 && (!processAlive || now - lastHeartbeat > 30)
    }
}
