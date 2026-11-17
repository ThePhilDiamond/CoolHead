import Foundation

/// When "Run it cooler" helps (research rule 14). It sets a process to background priority (`taskpolicy -b`), which keeps
/// it on the efficiency cores: that does nothing for work already at background priority, and can't speed anything up
/// (Howard Oakley, Eclectic Light, 9 May 2025, tested; the `taskpolicy` man page). So it is offered only for your own
/// process whose busy threads run above background priority, and never for macOS's own programs. A virtual machine's
/// work runs at high priority, so slowing its host slows everything inside it sharply: the option says so.
public enum RunCooler {
    /// Its busy work is already at background priority (90% or more of its busy CPU at priority 4 or lower, from `ps -M`);
    /// nil when too little is busy to tell. Readable for your own processes.
    public static func alreadyBackground(_ pid: pid_t) -> Bool? {
        BackgroundWork.cool(BackgroundWork.threads(pid), efficiencyCores: 0)
    }

    /// A virtual machine's host process: QEMU (UTM and others), Parallels, VMware Fusion, VirtualBox, and macOS's own
    /// virtualization service that apps such as UTM, Tart and Lima use.
    public static func isVirtualMachine(_ e: Evidence) -> Bool {
        let s = ((e.path ?? "") + " " + e.name).lowercased()
        return ["qemu-system", "/utm.app/", "prl_vm_app", "/parallels desktop.app/", "vmware-vmx", "/vmware fusion.app/",
                "vboxheadless", "virtualboxvm", "com.apple.virtualization.virtualmachine"].contains { s.contains($0) }
    }

    /// What the option says it costs.
    public static func consequence(_ e: Evidence) -> String {
        isVirtualMachine(e) ? "Everything running inside it slows down sharply. Undo any time." : "Slower, but less heat. Undo any time."
    }

    /// Whether to offer it at all: your own process, busy, not one of macOS's own programs, and not already at background
    /// priority.
    public static func offered(_ e: Evidence) -> Bool {
        let macOS = e.script == nil && (e.path.map(CaseReport.isMacOS) ?? true)
        return e.mine && e.coresNow >= 0.5 && !macOS && e.atBackgroundPriority != true
    }
}
