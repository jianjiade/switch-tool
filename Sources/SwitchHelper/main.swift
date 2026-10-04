import Foundation
import Darwin
import SystemConfiguration
import PowerCore
import SMCBridge

// Single serial loop owns all SMC mutations. IPC accepts fixed commands only.
guard geteuid() == 0 else { fputs("SwitchHelper requires root\n", stderr); exit(1) }
var adapter: Adapter?
var failure: String?
do { adapter = try Adapter(); try adapter?.set(enabled: true) }
catch { failure = error.localizedDescription }
var cycle = Cycle()
var lease = Lease()
var state = Status()
var restorePending = true
var switchedAt = st_awake_time()
let monitor = PowerMonitor()
monitor.start()
func restore() {
    cycle.stop(); lease.release()
    do { try adapter?.set(enabled: true); restorePending = false }
    catch { failure = "恢复外接供电失败：\(error.localizedDescription)"; restorePending = true }
}
func tick() {
    do {
        state = try Battery.snapshot()
        if cycle.phase != .idle && lease.expired(now: st_awake_time(), processAlive: kill(lease.owner, 0) == 0) { restore() }
        if monitor.consumeDisconnect() && cycle.phase != .idle { restore() }
        let previous = cycle.phase
        cycle.update(percent: state.percent, connected: state.connected)
        if previous != cycle.phase {
            if cycle.phase == .idle { restore() }
            else { try adapter?.set(enabled: cycle.adapterEnabled); switchedAt = st_awake_time() }
        }
        if cycle.phase != .idle && st_awake_time() - switchedAt > 15 {
            let expectedSource = cycle.adapterEnabled ? "外接电源" : "内置电池"
            if state.source != expectedSource {
                throw PowerError.message("实际供电来源未切换到\(expectedSource)，已停止控制")
            }
        }
        if restorePending { restore() }
    } catch { state = Status(); failure = error.localizedDescription; restore() }
    state.phase = cycle.phase; state.supported = adapter != nil && !restorePending
    state.error = failure
}
let server = st_listen()
guard server >= 0 else { restore(); exit(1) }
let shutdown = ShutdownFlag()
signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
term.setEventHandler { shutdown.stop() }; term.resume()
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
interrupt.setEventHandler { shutdown.stop() }; interrupt.resume()
while !shutdown.isStopped {
    tick()
    var poller = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
    guard poll(&poller, 1, 2000) > 0 else { continue }
    let fd = accept(server, nil, nil)
    guard fd >= 0 else { continue }
    var uid: UInt32 = 0; var pid: Int32 = 0
    var consoleUID: uid_t = 0
    _ = SCDynamicStoreCopyConsoleUser(nil, &consoleUID, nil)
    if st_peer(fd, &uid, &pid) == 0 && uid == consoleUID && uid != 0 {
        var buffer = [UInt8](repeating: 0, count: 64)
        // Accepted sockets need their own receive deadline.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        let count = read(fd, &buffer, buffer.count)
        let command = count > 0 ? String(decoding: buffer.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        switch command {
        case "start":
            if cycle.phase != .idle && lease.owner != pid { failure = "另一实例正在控制供电" }
            else if adapter != nil && state.connected && monitor.isMonitoring {
                do {
                    cycle.start(percent: state.percent)
                    try adapter?.set(enabled: cycle.adapterEnabled)
                    lease.claim(pid: pid, now: st_awake_time()); switchedAt = st_awake_time(); failure = nil
                } catch { failure = error.localizedDescription; restore() }
            } else { failure = state.connected ? "此设备不支持供电控制" : "请先连接适配器" }
        case "stop": if lease.owner == pid || cycle.phase == .idle { restore() }
        case "heartbeat": lease.renew(pid: pid, now: st_awake_time())
        case "status": break
        default: break
        }
        tick()
        state.ownsControl = lease.owner == pid && cycle.phase != .idle
        if var data = try? JSONEncoder().encode(state) {
            data.append(10)
            data.withUnsafeBytes { ptr in
                if let base = ptr.baseAddress { _ = send(fd, base, ptr.count, 0) }
            }
        }
    }
    close(fd)
}
restore(); close(server); st_smc_close()
