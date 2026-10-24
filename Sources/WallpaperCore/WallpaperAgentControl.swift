import Darwin
import Foundation

/// Injectable so transaction tests never signal the user's wallpaper agent.
public protocol WallpaperAgentControlling: AnyObject {
    func suspend() throws
    func reload() throws
    func resume()
}

public final class WallpaperAgentControl: WallpaperAgentControlling {
    private var suspendedPID: pid_t?
    private var watchdog: Process?

    public init() {}
    deinit { resume() }

    public func suspend() throws {
        if suspendedPID != nil { return }
        let pid = try agentPID()
        // An independent child resumes the daemon even if this app crashes during the short write window.
        let watchdog = Process()
        watchdog.executableURL = URL(fileURLWithPath: "/bin/sh")
        watchdog.arguments = ["-c", "/bin/sleep 3; /bin/kill -CONT \"$1\" 2>/dev/null", "wallpaper-resume", String(pid)]
        watchdog.standardOutput = FileHandle.nullDevice
        watchdog.standardError = FileHandle.nullDevice
        try watchdog.run()
        self.watchdog = watchdog
        suspendedPID = pid
        guard kill(pid, SIGSTOP) == 0 else { resume(); throw DirectWallpaperError.agentControlFailed }
        let deadline = Date().addingTimeInterval(0.5)
        repeat {
            var info = kinfo_proc()
            var length = MemoryLayout<kinfo_proc>.stride
            var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            if sysctl(&query, UInt32(query.count), &info, &length, nil, 0) == 0,
               length > 0, Int32(info.kp_proc.p_stat) == SSTOP { return }
            Thread.sleep(forTimeInterval: 0.01)
        } while Date() < deadline
        resume()
        throw DirectWallpaperError.agentControlFailed
    }

    public func reload() throws {
        guard let pid = suspendedPID else { throw DirectWallpaperError.agentControlFailed }
        guard kill(pid, SIGCONT) == 0 else { resume(); throw DirectWallpaperError.reloadFailed }
        let sent = kill(pid, SIGTERM) == 0
        suspendedPID = nil
        cancelWatchdog()
        guard sent else { throw DirectWallpaperError.reloadFailed }
        // launchd starts the agent again. Do not report a successful reload until the new process exists.
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if let replacement = try? agentPID(), replacement != pid { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw DirectWallpaperError.reloadFailed
    }

    public func resume() {
        if let pid = suspendedPID { _ = kill(pid, SIGCONT) }
        suspendedPID = nil
        cancelWatchdog()
    }

    private func cancelWatchdog() {
        if watchdog?.isRunning == true { watchdog?.terminate() }
        watchdog = nil
    }

    private func agentPID() throws -> pid_t {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-u", String(getuid()), "-x", "WallpaperAgent"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let pids = String(decoding: output, as: UTF8.self).split(whereSeparator: \.isWhitespace).compactMap { pid_t($0) }
        guard process.terminationStatus == 0, pids.count == 1, let pid = pids.first, pid > 1 else {
            throw DirectWallpaperError.agentUnavailable
        }
        var executable = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &executable, UInt32(executable.count)) > 0 else { throw DirectWallpaperError.agentUnavailable }
        let executablePath = String(cString: executable)
        guard executablePath.hasPrefix("/System/Library/"), URL(fileURLWithPath: executablePath).lastPathComponent == "WallpaperAgent" else {
            throw DirectWallpaperError.agentUnavailable
        }
        return pid
    }
}
