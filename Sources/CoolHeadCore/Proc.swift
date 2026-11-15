import Darwin
import Foundation

/// Reads facts about one process from the kernel. Everything here works without an administrator password for the
/// user's own processes; for other users' and system processes some calls return nil.
public enum Proc {
    public struct BSD {
        public let pid: pid_t
        public let ppid: pid_t
        public let uid: uid_t
        public let name: String
        public let start: Date
        /// Frozen with SIGSTOP (Cool Head's "Pause until you plug in").
        public var stopped = false
    }

    public struct Usage {
        /// Total CPU time used since the process started, in seconds.
        public let cpuSeconds: Double
        /// CPU time on the performance cores, in seconds (the cores that draw most of the power).
        public let pCoreSeconds: Double
        /// Memory the process is charged for, in bytes (what Activity Monitor calls Memory).
        public let footprint: UInt64
        public let diskWritten: UInt64
        /// Energy used since start, in nanojoules.
        public let energyNJ: UInt64
    }

    public struct OpenFile {
        public let fd: Int32
        public let path: String
        public let writable: Bool
    }

    static let timebase: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    /// Recent CPU use, in percent of one core, for every process, from /bin/ps (which can read other users'
    /// processes where our own calls can't). Used only for processes our own calls can't read.
    public static func psCPU() -> [pid_t: Double] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-A", "-o", "pid=,%cpu="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        var out: [pid_t: Double] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            if f.count >= 2, let p = pid_t(f[0]), let c = Double(f[1].replacingOccurrences(of: ",", with: ".")) { out[p] = c }
        }
        return out
    }

    /// The process's scheduling priority (what `ps -o pri` shows): about 31 normally, 4 in macOS's background
    /// band. This is how to confirm "Run it cooler" took effect: getpriority(PRIO_DARWIN_PROCESS) always reports 0
    /// for other processes, whatever their setting.
    public static func schedulingPriority(_ pid: pid_t) -> Int? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return Int(info.pti_priority)
    }

    public static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var buf = [pid_t](repeating: 0, count: Int(n) + 128)
        let got = buf.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        return Array(buf.prefix(Int(max(got, 0)))).filter { $0 > 0 }
    }

    public static func bsd(_ pid: pid_t) -> BSD? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        var name = cstr(info.pbi_name)
        if name.isEmpty { name = cstr(info.pbi_comm) }
        let start = Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1e6)
        var b = BSD(pid: pid, ppid: pid_t(info.pbi_ppid), uid: info.pbi_uid, name: name, start: start)
        b.stopped = info.pbi_status == 4      // SSTOP
        return b
    }

    public static func path(_ pid: pid_t) -> String? {
        var buf = [UInt8](repeating: 0, count: 4 * 1024)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard n > 0 else { return nil }
        return String(decoding: buf.prefix(Int(n)), as: UTF8.self)
    }

    /// The command line: argv, from KERN_PROCARGS2.
    public static func args(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = 4
        while i < size && buf[i] != 0 { i += 1 }      // the executable path
        while i < size && buf[i] == 0 { i += 1 }      // its padding
        var out: [String] = []
        while out.count < argc && i < size {
            let s = i
            while i < size && buf[i] != 0 { i += 1 }
            out.append(String(decoding: buf[s..<i], as: UTF8.self))
            i += 1
        }
        return out
    }

    public static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let p = cstr(info.pvi_cdir.vip_path)
        return p.isEmpty ? nil : p
    }

    public static func usage(_ pid: pid_t) -> Usage? {
        var ri = rusage_info_v6()
        let r = withUnsafeMutablePointer(to: &ri) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
        }
        guard r == 0 else { return nil }
        let total = Double(ri.ri_user_time &+ ri.ri_system_time) * timebase / 1e9
        let pcore = Double(ri.ri_user_ptime &+ ri.ri_system_ptime) * timebase / 1e9
        return Usage(cpuSeconds: total, pCoreSeconds: pcore, footprint: ri.ri_phys_footprint,
                     diskWritten: ri.ri_diskio_byteswritten, energyNJ: ri.ri_energy_nj)
    }

    /// Regular files the process has open, and whether each is open for writing.
    public static func openFiles(_ pid: pid_t) -> [OpenFile] {
        let n = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard n > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(n) / stride + 16)
        let got = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard got > 0 else { return [] }
        var out: [OpenFile] = []
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == 1 {      // PROX_FDTYPE_VNODE
            var vi = vnode_fdinfowithpath()
            let sz = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &vi, sz) == sz else { continue }
            let path = cstr(vi.pvip.vip_path)
            guard !path.isEmpty else { continue }
            out.append(OpenFile(fd: fd.proc_fd, path: path, writable: (vi.pfi.fi_openflags & 0x2) != 0))   // FWRITE
        }
        return out
    }
}

/// A fixed-size C char array (imported as a tuple) to a String, stopping at the first zero byte.
func cstr<T>(_ tuple: T) -> String {
    withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
}
