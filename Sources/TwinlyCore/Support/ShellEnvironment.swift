import Foundation

public enum ShellEnvironment {
    public static let cliMarker = "# twinly-cli-profile"

    public static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func isValidEnvName(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
    }

    public static func isValidCommandName(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    /// True if the file at `path` is a script written by Twinly.
    public static func hasTwinlyMarker(path: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data.prefix(2048), encoding: .utf8) else { return false }
        return text.contains(cliMarker)
    }

    private static let pathLock = NSLock()
    private static var cachedLoginPATH: String??

    /// PATH as seen by the user's interactive login shell. Cached after the first call. Blocking: call off the main thread.
    public static func loginShellPATH(timeout: TimeInterval = 3) -> String? {
        pathLock.lock()
        if let cached = cachedLoginPATH {
            pathLock.unlock()
            return cached
        }
        pathLock.unlock()

        let result = runLoginShellForPATH(timeout: timeout)

        pathLock.lock()
        cachedLoginPATH = .some(result)
        pathLock.unlock()
        return result
    }

    private static func runLoginShellForPATH(timeout: TimeInterval) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '__TWINLY__%s__TWINLY__' \"$PATH\""]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }

        var collected = Data()
        let readQueue = DispatchQueue(label: "twinly.loginpath.read")
        let readDone = DispatchSemaphore(value: 0)
        readQueue.async {
            collected = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
        }
        _ = readDone.wait(timeout: .now() + 1)

        guard let text = String(data: collected, encoding: .utf8) else { return nil }
        let marker = "__TWINLY__"
        guard let start = text.range(of: marker),
              let end = text.range(of: marker, range: start.upperBound..<text.endIndex) else { return nil }
        let value = String(text[start.upperBound..<end.lowerBound])
        return value.isEmpty ? nil : value
    }

    /// The directories to search for binaries: login-shell PATH first, then the process PATH.
    public static func searchPathEntries() -> [String] {
        var entries: [String] = []
        if let login = loginShellPATH() { entries += login.split(separator: ":").map(String.init) }
        if let env = ProcessInfo.processInfo.environment["PATH"] { entries += env.split(separator: ":").map(String.init) }
        var seen = Set<String>()
        return entries.filter { seen.insert($0).inserted }
    }

    public static func rcFileForCurrentShell() -> String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if shell.hasSuffix("zsh") { return "~/.zshrc" }
        if shell.hasSuffix("bash") { return "~/.bash_profile" }
        return "~/.profile"
    }

    public static func pathFixCommand() -> String {
        let rc = rcFileForCurrentShell()
        return "grep -qs '.local/bin' \(rc) || echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> \(rc)"
    }
}
