import AppKit
import Foundation
import PowerCore

func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private let queue = DispatchQueue(label: "dev.switchtool.client")
    private var latest = Status()
    private var available = false
    private var busy = false
    private var active = false
    private var terminating = false
    private var detail = "正在连接后台组件…"
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak owner = self] _ in owner?.refresh() }
    }
    private func refresh() { request(active ? "heartbeat" : "status") }
    private func request(_ command: String) {
        guard !busy, !terminating else { return }
        busy = true
        queue.async {
            let result = Result { try IPC.request(command) }
            let battery: Status?
            if case .failure = result { battery = try? Battery.snapshot() } else { battery = nil }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let status):
                    self.latest = status; self.available = true
                    self.active = status.ownsControl && status.phase != .idle
                    self.detail = status.error ?? ""
                case .failure(let error):
                    self.available = false; self.active = false
                    if let battery { self.latest = battery }
                    self.detail = error.localizedDescription
                }
                self.render()
            }
        }
    }
    private func render() {
        item.button?.title = "⚡ \(latest.percent)%"
        let menu = NSMenu()
        func label(_ title: String) { let entry = NSMenuItem(title: title, action: nil, keyEquivalent: ""); entry.isEnabled = false; menu.addItem(entry) }
        label("Switch Tool")
        label("电量：\(latest.percent)% · \(latest.source)")
        label("适配器：\(latest.connected ? "已连接" : "未连接")")
        let phase: String
        switch latest.phase {
        case .idle: phase = "控制已停止"
        case .discharging: phase = "电池供电 · 低于 10% 后充电"
        case .charging: phase = latest.charging ? "正在充电 · 100% 后切回电池" : "外接供电 · 等待系统充电至 100%"
        }
        label(phase)
        if !detail.isEmpty { label(String(detail.prefix(90))) }
        if available && latest.phase != .idle && !latest.ownsControl { label("另一 App 实例正在控制供电") }
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: active ? "停止并恢复外接供电" : "开启自动循环", action: #selector(toggleControl), keyEquivalent: "")
        toggle.target = self; toggle.isEnabled = available && latest.supported && (latest.connected || active) && (latest.phase == .idle || latest.ownsControl) && !busy
        menu.addItem(toggle)
        let install = NSMenuItem(title: "安装／更新后台组件…", action: #selector(installHelper), keyEquivalent: "")
        install.target = self; install.isEnabled = latest.phase == .idle && !busy; menu.addItem(install)
        let about = NSMenuItem(title: "关于与使用说明", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出并恢复外接供电", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu
    }
    @objc private func toggleControl() { request(active ? "stop" : "start") }
    @objc private func installHelper() {
        guard let script = Bundle.main.path(forResource: "install-helper", ofType: "sh"),
              let helper = Bundle.main.path(forResource: "SwitchHelper", ofType: nil) else {
            detail = "请运行打包后的 Switch Tool.app"; render(); return
        }
        busy = true; render()
        let command = "/bin/sh \(shellQuote(script)) \(shellQuote(helper))"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // NSAppleScript execution stays on the AppKit main thread.
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        busy = false
        if let message = error?[NSAppleScript.errorMessage] as? String { detail = message; render() }
        else { refresh() }
    }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Switch Tool"
        alert.informativeText = "手动开启后，插电时使用内置电池；低于 10% 恢复外接供电，充至 100% 后继续循环。\n\n拔掉适配器会停止控制；合盖尽量保持当前阶段，可能影响外接显示器。退出或 App 失联后后台恢复外接供电。\n\n系统暂缓充电时会继续等待。供电控制能力以当前机型和固件检测结果为准。"
        alert.runModal()
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        terminating = true; timer?.invalidate()
        queue.async {
            let result = Result { try IPC.request("stop") }
            DispatchQueue.main.async {
                let message: String?
                switch result {
                case .success(let status): message = !status.supported ? status.error : nil
                case .failure(let error): message = "无法确认外接供电已恢复：\(error.localizedDescription)。后台若仍运行，会在失联后尝试恢复。"
                }
                if let message {
                    let alert = NSAlert(); alert.messageText = "外接供电恢复未确认"; alert.informativeText = message
                    alert.addButton(withTitle: "返回 App")
                    alert.addButton(withTitle: "仍然退出")
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.terminating = false
                        self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak owner = self] _ in owner?.refresh() }
                        sender.reply(toApplicationShouldTerminate: false)
                    } else { sender.reply(toApplicationShouldTerminate: true) }
                } else { sender.reply(toApplicationShouldTerminate: true) }
            }
        }
        return .terminateLater
    }
}
if CommandLine.arguments.contains("--diagnostics") {
    do {
        let snapshot = try Battery.snapshot()
        let data = try JSONEncoder().encode(snapshot)
        print(String(decoding: data, as: UTF8.self))
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
