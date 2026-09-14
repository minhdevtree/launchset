import Foundation

/// The `launchset` command talks to the running app over a Unix socket in the app's data folder.
public struct CLIRequest: Codable, Sendable {
    public var args: [String]
    public init(args: [String]) { self.args = args }
}

public struct CLIResponse: Codable, Sendable {
    public var output: String
    public var exitCode: Int32
    public init(output: String, exitCode: Int32 = 0) {
        self.output = output
        self.exitCode = exitCode
    }
}

public struct SocketError: Error, CustomStringConvertible {
    public let call: String
    public let code: Int32
    public var description: String { "\(call): \(String(cString: strerror(code)))" }
}

public enum CLI {
    public static let dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("LaunchSet")
    public static var socketPath: String { dataDirectory.appendingPathComponent("cli.sock").path }

    public static let usage = """
    Usage: launchset [command]

      status                   Next run, pending closes and groups (default)
      groups                   Apps in each group with their role and state
      open <group>             Open a group
      close <group> [--force]  Close a group. --force quits apps without waiting
      pause                    Pause all schedules
      resume                   Resume schedules. Missed runs don't catch up
      snooze <group>           Push back a pending scheduled close
      skip <group>             Skip a pending scheduled close
      schedules                List schedules and their next run
      history [count]          Show recent runs, 10 by default

    Group names are matched without case, and can contain spaces without quotes.
    """

    /// Rows padded into aligned columns, two spaces apart. Trailing spaces are trimmed.
    public static func table(_ rows: [[String]], indent: String = "") -> String {
        let widths = rows.reduce(into: [Int]()) { widths, row in
            for (i, cell) in row.enumerated() {
                if i < widths.count { widths[i] = max(widths[i], cell.count) } else { widths.append(cell.count) }
            }
        }
        return rows.map { row in
            let line = row.enumerated().map { i, cell in cell.padding(toLength: widths[i], withPad: " ", startingAt: 0) }
                .joined(separator: "  ")
            return indent + line.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }.joined(separator: "\n")
    }

    // MARK: Socket

    /// Client side: sends one request and waits for the reply.
    public static func send(_ request: CLIRequest, to path: String = socketPath) throws -> CLIResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError(call: "socket", code: errno) }
        defer { close(fd) }
        try withAddress(path) { addr, len in
            if connect(fd, addr, len) != 0 { throw SocketError(call: "connect", code: errno) }
        }
        try writeAll(fd, JSON.encoder().encode(request))
        shutdown(fd, SHUT_WR)
        return try JSON.decoder().decode(CLIResponse.self, from: readAll(fd))
    }

    /// Server side: a listening socket only the current user can connect to.
    public static func makeListener(at path: String = socketPath) throws -> Int32 {
        unlink(path) // left behind if the app crashed
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError(call: "socket", code: errno) }
        do {
            try withAddress(path) { addr, len in
                if bind(fd, addr, len) != 0 { throw SocketError(call: "bind", code: errno) }
            }
            guard chmod(path, 0o600) == 0 else { throw SocketError(call: "chmod", code: errno) }
            guard Darwin.listen(fd, 8) == 0 else { throw SocketError(call: "listen", code: errno) }
        } catch {
            close(fd)
            throw error
        }
        return fd
    }

    public static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 { throw SocketError(call: "write", code: errno) }
                offset += n
            }
        }
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Void) throws {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw SocketError(call: "socket path", code: ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        addr.sun_len = UInt8(len)
        try withUnsafePointer(to: &addr) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { try body($0, len) }
        }
    }
}
