# Switch Tool

Apple Silicon MacBook 的原生 macOS 菜单栏供电控制 App（macOS 13+）。

手动开启后，插着电源适配器时使用内置电池；电量**低于 10%**后恢复适配器供电，充至 **100%** 后再次切回电池。开启时低于 10% 会先充电。系统优化充电或温度限制导致暂缓充电时，保持外接供电并等待，不绕过系统策略。

## 使用

```sh
./scripts/build-app.sh
open "dist/Switch Tool.app"
```

1. 点击菜单栏的 `⚡ 电量%`。
2. 选择「安装／更新后台组件…」，在 macOS 授权对话框中输入管理员凭证。
3. 连接适配器，选择「开启自动循环」。
4. 选择「停止并恢复外接供电」或退出 App，结束控制。

已构建的 App 位于 `dist/Switch Tool.app`。构建脚本优先使用 `/Applications/Xcode.app`，不修改全局 xcode-select。需要完整 Xcode 运行 XCTest；普通 App 编译也可使用 Command Line Tools。当前本地包使用 ad-hoc 签名，未进行 Developer ID 签名、公证或 App Store 发布。

## 行为

- 10% 时继续电池供电，低于 10% 才充电；充电阶段不会在中间电量重新切回电池。
- 拔掉适配器会结束本次控制，再插回需要手动开启。
- 合盖和睡眠不主动恢复供电；系统可能因此让合盖外接显示器进入睡眠。无法承诺睡眠期间持续执行切换，唤醒后立即处理当前电量。
- 电源变化通知与轮询共同检测拔电。若在深度睡眠期间完成拔出并重新插入，且系统未交付断开通知，App 无法证明这次插拔，可能继续原来的循环。
- 正常退出请求后台恢复供电；App 崩溃或失联超过 30 秒的清醒时间，后台尝试恢复。后台进程被强杀后由 launchd 重启，并在启动时恢复供电。恢复失败会继续尝试并显示错误，不能保证硬件或固件拒绝写入时成功恢复。
- 只有当前控制实例可续约或停止其会话；第二实例可以查看状态，不能接管。
- 菜单显示实际供电来源。SMC 写入会回读，切换后给系统 15 秒更新供电来源，来源不符合预期则停止并恢复。

## 技术结构

- `Sources/SwitchTool`：AppKit 菜单栏、管理员安装授权、状态和控制按钮。
- `Sources/SwitchHelper`：root launch daemon，串行处理 SMC 写入、阈值循环和失联恢复。
- `Sources/PowerCore`：状态机、会话租约、电池读取、电源通知和 IPC。
- `Sources/SMCBridge`：IOKit AppleSMC 与 Unix-domain socket。

后台只接受 `status`、`start`、`stop`、`heartbeat` 固定指令，不接受路径、脚本或任意 SMC key。socket 通过内核 peer UID/PID 获取调用身份，只接受当前登录桌面用户。权限边界是登录用户：同用户进程可发起电池控制，不声称做了应用签名级身份隔离。后台不保存会话，重启恢复供电后保持停止。

SMC 为非公开控制接口。按 `CH0I`、`CH0J`、`CHIE` 顺序探测，要求单字节、已知取值，禁止通过关闭 SIP 获取能力。读取可用不代表写入被固件允许，开启时会验证写入和供电来源；Intel 明确不支持。

接口研究来源（实现为本项目独立代码，没有复制第三方实现）：
- [batt 适配器控制](https://github.com/charlie0129/batt/blob/master/pkg/smc/adapter.go)
- [batt Apple Silicon key](https://github.com/charlie0129/batt/blob/master/pkg/smc/consts_arm64.go)
- [gosmc Darwin 驱动 ABI](https://github.com/charlie0129/gosmc/blob/master/driver_darwin.go)

## 验证与卸载

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
"dist/Switch Tool.app/Contents/MacOS/SwitchTool" --diagnostics
sudo ./scripts/uninstall-helper.sh
```

`--diagnostics` 只读电量、物理连接状态和供电来源，不写 SMC，不启动 UI，不输出序列号。卸载前应先在 App 中停止控制，并确认显示外接供电。

本地验证覆盖状态机边界、完整循环、低电量启动、拔电停止、不自动重启、会话所有者续约、失联和睡眠时钟。真实 SMC 写入、100% 完整循环、合盖及异常恢复需要管理员安装后的设备验证，编译和单元测试不能替代这些验证。
# switch-tool
