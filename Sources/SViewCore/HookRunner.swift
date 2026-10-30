import Foundation

/// Result of a `:run` hook or `:run-shell` line.
public struct HookResult: Sendable, Equatable {
    public let command: String
    public let status: Int32
    public let output: String
    public let timedOut: Bool
}

/// Runs hook commands (SV-603) with `/bin/sh -c` in the current folder.
/// The current file, the folder and the marked files are passed as the
/// environment variables FILE, FOLDER and MARKED (one path per line), so
/// `"$FILE"` in a hook is expanded by the shell and odd file names cannot
/// inject commands. Output is stdout and stderr together, capped.
public enum HookRunner {
    public static let outputLimit = 512 * 1024

    @concurrent
    public static func run(
        _ command: String,
        file: URL?,
        folder: URL?,
        marked: [URL],
        timeout: Duration = .seconds(120)
    ) async -> HookResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        if let folder {
            process.currentDirectoryURL = folder
        }
        var environment = ProcessInfo.processInfo.environment
        environment["FILE"] = file?.path ?? ""
        environment["FOLDER"] = folder?.path ?? ""
        environment["MARKED"] = marked.map(\.path).joined(separator: "\n")
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return HookResult(command: command, status: -1, output: "cannot start /bin/sh: \(error)", timedOut: false)
        }
        let reader = Task.detached { () -> Data in
            pipe.fileHandleForReading.readDataToEndOfFile()
        }
        let watchdog = Task.detached {
            try await Task.sleep(for: timeout)
            if process.isRunning {
                process.terminate()
                return true
            }
            return false
        }
        let data = await reader.value
        process.waitUntilExit()
        watchdog.cancel()
        let timedOut = (try? await watchdog.value) ?? false
        var output = String(decoding: data.prefix(outputLimit), as: UTF8.self)
        if data.count > outputLimit {
            output += "\n[output cut at \(outputLimit / 1024) KB]"
        }
        return HookResult(
            command: command,
            status: process.terminationStatus,
            output: output,
            timedOut: timedOut
        )
    }
}
