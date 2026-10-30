import Foundation

/// Runs a command off the main thread and collects its output. `onLine`
/// receives stdout line by line as it arrives, for long-running commands
/// like `nord-docker-proxy login` whose progress the menu shows live.
enum CLI {
    struct Result: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    static func run(
        _ path: String, _ args: [String],
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice

            let collected = LineCollector(onLine: onLine)
            out.fileHandleForReading.readabilityHandler = { handle in
                collected.append(handle.availableData)
            }
            process.terminationHandler = { p in
                out.fileHandleForReading.readabilityHandler = nil
                collected.append(out.fileHandleForReading.readDataToEndOfFile())
                let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: Result(
                    exitCode: p.terminationStatus,
                    stdout: collected.text,
                    stderr: errText.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
            } catch {
                out.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: Result(
                    exitCode: -1, stdout: "", stderr: "cannot run \(path): \(error.localizedDescription)"))
            }
        }
    }
}

/// Thread-safe accumulator that also splits stdout into lines for `onLine`.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = Data()
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        var lines: [String] = []
        lock.lock()
        data.append(chunk)
        pending.append(chunk)
        while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: pending[pending.startIndex..<nl], as: UTF8.self))
            pending.removeSubrange(pending.startIndex...nl)
        }
        lock.unlock()
        lines.forEach { onLine?($0) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
