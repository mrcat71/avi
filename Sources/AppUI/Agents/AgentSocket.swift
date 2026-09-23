import Darwin
import Foundation

public enum AgentSocketError: Error, Equatable, LocalizedError {
    case pathTooLong(String)
    case servedElsewhere(String)
    case notASocket(String)
    case system(call: String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .pathTooLong(let path):
            return "The socket path is longer than macOS allows (\(UnixSocketAddress.maxPathLength) bytes): \(path)"
        case .servedElsewhere(let path):
            return "Another Avi instance already listens on \(path)."
        case .notASocket(let path):
            return "\(path) exists and is not a socket, so Avi leaves it alone."
        case .system(let call, let errno):
            return "\(call) failed: \(String(cString: strerror(errno)))"
        }
    }
}

enum UnixSocketAddress {
    /// `sun_path` holds 104 bytes including the terminating NUL.
    static let maxPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) throws -> T {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathLength else { throw AgentSocketError.pathTooLong(path) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}

/// Listens on a unix socket and answers each connection with `handler`.
///
/// Only processes running as the same user get an answer: the socket file is
/// 0600, and every peer's user ID is checked again after `accept`. Each
/// connection is served on its own, so a slow request never blocks another.
public final class AgentSocketServer: @unchecked Sendable {
    public typealias Handler = @Sendable (Data) async -> Data

    public let path: String
    private let handler: Handler
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var boundInode: ino_t = 0
    private let queue = DispatchQueue(label: "com.avi.agent-socket.accept")

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public func start() throws {
        guard path.utf8.count <= UnixSocketAddress.maxPathLength else { throw AgentSocketError.pathTooLong(path) }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try clearStaleSocket()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSocketError.system(call: "socket", errno: errno) }
        // Git and AI subprocesses must never inherit the listening socket.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // Set here so accepted sockets inherit it: setting it after accept fails
        // once the peer has hung up (a probe does), and the reply would then
        // kill the app with SIGPIPE.
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        // Bind under a private name, restrict it, then move it into place, so the
        // socket is never reachable with looser permissions. A short name keeps
        // the temporary path within the same length limit as the real one.
        var temporary = (directory as NSString).appendingPathComponent(".avi-\(getpid())")
        if temporary.utf8.count > UnixSocketAddress.maxPathLength {
            temporary = path
        }
        unlink(temporary)
        do {
            let bound = try UnixSocketAddress.withAddress(temporary) { bind(fd, $0, $1) }
            guard bound == 0 else { throw AgentSocketError.system(call: "bind", errno: errno) }
            guard chmod(temporary, 0o600) == 0 else { throw AgentSocketError.system(call: "chmod", errno: errno) }
            if temporary != path {
                guard rename(temporary, path) == 0 else { throw AgentSocketError.system(call: "rename", errno: errno) }
            }
            guard listen(fd, 16) == 0 else { throw AgentSocketError.system(call: "listen", errno: errno) }
        } catch {
            close(fd)
            if temporary != path {
                unlink(temporary)
            }
            throw error
        }

        var info = stat()
        if lstat(path, &info) == 0 {
            boundInode = info.st_ino
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPending(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        lock.withLock { self.source = source }
        source.resume()
    }

    /// Stops listening and removes the socket file, unless another instance has
    /// since replaced it with its own.
    public func stop() {
        let source = lock.withLock { () -> DispatchSourceRead? in
            defer { self.source = nil }
            return self.source
        }
        source?.cancel()
        var info = stat()
        if boundInode != 0, lstat(path, &info) == 0, info.st_ino == boundInode {
            unlink(path)
        }
        boundInode = 0
    }

    private func clearStaleSocket() throws {
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw AgentSocketError.notASocket(path) }
        if AgentClient.isReachable(path) {
            throw AgentSocketError.servedElsewhere(path)
        }
        unlink(path)
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            // Accepted sockets inherit O_NONBLOCK and SO_NOSIGPIPE from the
            // listener; reads below block with a timeout instead.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)

            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
                close(client)
                continue
            }
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            let handler = handler
            DispatchQueue.global(qos: .userInitiated).async {
                let request = SocketIO.readLine(from: client, limit: AgentProtocol.maxRequestBytes) ?? Data()
                Task.detached {
                    var response = await handler(request)
                    response.append(0x0A)
                    SocketIO.write(response, to: client)
                    close(client)
                }
            }
        }
    }
}

/// Talks to a running Avi from the `avi` command.
public enum AgentClient {
    public enum Failure: Error, Equatable {
        /// Nothing listens on the socket: Avi is not running, or its bridge is off.
        case notRunning
        /// The connection was refused by permissions or a sandbox.
        case blocked(errno: Int32)
        case timedOut
        case io(String)
        case badResponse(String)
    }

    public static func isReachable(_ path: String) -> Bool {
        guard let fd = try? connect(to: path) else { return false }
        close(fd)
        return true
    }

    public static func send(_ request: AgentRequest, to path: String, timeout: TimeInterval = 60) throws -> AgentResponse {
        let fd = try connect(to: path)
        defer { close(fd) }
        var seconds = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &seconds, socklen_t(MemoryLayout<timeval>.size))

        var payload = try AgentProtocol.encoder.encode(request)
        payload.append(0x0A)
        guard SocketIO.write(payload, to: fd) else { throw Failure.io("Could not send the request.") }
        guard let line = SocketIO.readLine(from: fd, limit: 16 << 20) else {
            throw errno == EAGAIN || errno == EWOULDBLOCK ? Failure.timedOut : Failure.io("Could not read the reply.")
        }
        do {
            return try JSONDecoder().decode(AgentResponse.self, from: line)
        } catch {
            throw Failure.badResponse(String(decoding: line.prefix(200), as: UTF8.self))
        }
    }

    private static func connect(to path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw errno == EPERM || errno == EACCES ? Failure.blocked(errno: errno) : Failure.io(String(cString: strerror(errno)))
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let result: Int32
        do {
            result = try UnixSocketAddress.withAddress(path) { Darwin.connect(fd, $0, $1) }
        } catch {
            close(fd)
            throw Failure.io(error.localizedDescription)
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            switch code {
            case ENOENT, ECONNREFUSED, ENOTDIR:
                throw Failure.notRunning
            case EPERM, EACCES:
                throw Failure.blocked(errno: code)
            default:
                throw Failure.io(String(cString: strerror(code)))
            }
        }
        return fd
    }
}

enum SocketIO {
    /// Reads up to the first newline, or to end of stream. Nil on timeout,
    /// error, or when more than `limit` bytes arrive without a newline.
    static func readLine(from fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< count])
                if let newline = data.firstIndex(of: 0x0A) {
                    return data[data.startIndex ..< newline]
                }
                if data.count > limit {
                    return nil
                }
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                return nil
            }
        }
    }

    @discardableResult
    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return true }
            var remaining = raw.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }
}
