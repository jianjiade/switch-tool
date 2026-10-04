import Foundation
import IOKit.ps
// Power notifications latch an observed unplug until the control loop consumes it.
public final class PowerMonitor {
    private let lock = NSLock()
    private var unplugged = false
    private var monitoring = false
    public init() {}
    public func start() {
        Thread.detachNewThread { [self] in
            let context = Unmanaged.passUnretained(self).toOpaque()
            guard let source = IOPSNotificationCreateRunLoopSource({ pointer in
                guard let pointer else { return }
                let monitor = Unmanaged<PowerMonitor>.fromOpaque(pointer).takeUnretainedValue()
                if let status = try? Battery.snapshot(), !status.connected {
                    monitor.lock.lock(); monitor.unplugged = true; monitor.lock.unlock()
                }
            }, context)?.takeRetainedValue() else { return }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            lock.lock(); monitoring = true; lock.unlock()
            CFRunLoopRun()
        }
    }
    public func consumeDisconnect() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let value = unplugged; unplugged = false; return value
    }
    public var isMonitoring: Bool { lock.lock(); defer { lock.unlock() }; return monitoring }
}
public final class ShutdownFlag {
    private let lock = NSLock()
    private var stopped = false
    public init() {}
    public func stop() { lock.lock(); stopped = true; lock.unlock() }
    public var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
