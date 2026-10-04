import Foundation
import Darwin
import SMCBridge
public enum IPC {
    public static func request(_ command: String) throws -> Status {
        let fd = st_connect()
        guard fd >= 0 else { throw PowerError.message("后台组件未安装或未运行") }
        defer { close(fd) }
        let bytes = Array((command + "\n").utf8)
        guard write(fd, bytes, bytes.count) == bytes.count else { throw PowerError.message("发送指令失败") }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while result.count < 8192 {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
            if result.last == 10 { break }
        }
        return try JSONDecoder().decode(Status.self, from: result)
    }
}
