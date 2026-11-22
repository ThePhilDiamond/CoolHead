import Darwin

/// The socket calls for the link (see ChromeLink.swift): the host connects with `connect(to:)`, and the app listens
/// with `listen(at:)` and checks each connection with `peerIsThisUser`. Each side accepts only this user's: a page in
/// Chrome must not be able to reach another user's Cool Head, or be reached by another user's program pretending to be
/// Cool Head.
extension ChromeLink {
    /// A socket address for a path, or nil when the path doesn't fit in one (104 bytes on macOS).
    static func address(_ path: String) -> sockaddr_un? {
        var a = sockaddr_un()
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, !bytes.contains(0), bytes.count < MemoryLayout.size(ofValue: a.sun_path) else { return nil }
        a.sun_family = sa_family_t(AF_UNIX)
        a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &a.sun_path) { p in
            for (i, b) in bytes.enumerated() { p[i] = b }
        }
        return a
    }

    /// Whether the program at the other end of a connected Unix socket runs as this user, from the kernel's own
    /// record of who opened it (LOCAL_PEERCRED), which the other end can't change.
    public static func peerIsThisUser(_ fd: Int32) -> Bool {
        var cred = xucred()
        var size = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &cred, &size) == 0, cred.cr_version == XUCRED_VERSION else { return false }
        return cred.cr_uid == getuid()
    }

    /// Whether the file at a path is a socket (not a link to one) owned by this user and closed to every other user,
    /// as Cool Head makes it.
    static func socketFileIsThisUsers(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        return st.st_mode & S_IFMT == S_IFSOCK && st.st_uid == getuid() && st.st_mode & 0o077 == 0
    }

    /// Writes cut short after this long count as a dropped link, so neither side can hold the other up for good.
    static let sendTimeout = timeval(tv_sec: 5, tv_usec: 0)

    static func setOptions(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var t = sendTimeout
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, socklen_t(MemoryLayout<timeval>.size))
        // the descriptor isn't passed to anything this program starts (it starts nothing, but the app does)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    /// Connects to Cool Head's socket, only if it's this user's: the file must be this user's socket, closed to
    /// others, and the program listening must run as this user. Returns the connected descriptor, or nil.
    /// The file is checked before connecting, and the listener after, since the file could change in between.
    public static func connect(to path: String) -> Int32? {
        guard socketFileIsThisUsers(path), var a = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let r = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0, peerIsThisUser(fd) else { close(fd); return nil }
        setOptions(fd)
        return fd
    }

    /// Listens at a path, for the app and the selftest: replaces a socket left there by a run that ended without
    /// removing it (never any other kind of file), and makes the new one 600. The folder, which should be 700, is the
    /// caller's. Returns the listening descriptor, or nil.
    public static func listen(at path: String) -> Int32? {
        guard var a = address(path) else { return nil }
        var st = stat()
        if lstat(path, &st) == 0 {
            guard st.st_mode & S_IFMT == S_IFSOCK, st.st_uid == getuid() else { return nil }
            unlink(path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let r = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 4) == 0 else { close(fd); return nil }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        return fd
    }

    /// Accepts one connection on a listening socket, only from this user's programs; nil for anyone else's (closed at
    /// once) or on an error. Blocks until one comes, unless the listening socket is non-blocking.
    public static func accept(_ listener: Int32) -> Int32? {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return nil }
        guard peerIsThisUser(fd) else { close(fd); return nil }
        setOptions(fd)
        return fd
    }

    /// Writes every byte, through partial writes and interruptions; false if the other end has gone or a write timed
    /// out.
    public static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var done = 0
        while done < bytes.count {
            let n = bytes.withUnsafeBytes { write(fd, $0.baseAddress! + done, bytes.count - done) }
            if n > 0 { done += n } else if n < 0 && errno == EINTR { continue } else { return false }
        }
        return true
    }
}
