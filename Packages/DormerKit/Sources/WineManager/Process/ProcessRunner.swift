import Foundation
import os

/// Everything needed to start a child process.
public struct ProcessSpec: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    /// The complete environment. Nothing is inherited from Dormer's own environment.
    public var environment: [String: String]
    public var workingDirectory: URL?

    public init(executable: URL, arguments: [String], environment: [String: String], workingDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }
}

/// Output of a process that ran to completion.
public struct ProcessResult: Sendable, Equatable {
    public var status: Int32
    /// Standard output and standard error, interleaved, one entry per line.
    public var lines: [String]
}

/// A child process whose combined stdout/stderr is delivered line by line.
public final class RunningProcess: @unchecked Sendable {
    public let processIdentifier: Int32
    /// Finishes when the process closes its output, or shortly after it exits.
    public let lines: AsyncStream<String>

    private let process: Process
    private let state: OSAllocatedUnfairLock<State>

    private struct State {
        var exitStatus: Int32?
        var waiters: [CheckedContinuation<Int32, Never>] = []
        var buffer = Data()
        var outputFinished = false
    }

    /// Wine leaves helper processes such as `wineserver` running for a few seconds; they can keep
    /// the pipe open after the program itself exits. Stop reading this long after exit.
    static let outputGracePeriod: Duration = .milliseconds(1500)

    private init(process: Process, lines: AsyncStream<String>, state: OSAllocatedUnfairLock<State>) {
        self.process = process
        self.processIdentifier = process.processIdentifier
        self.lines = lines
        self.state = state
    }

    /// Starts `spec`. Throws if the executable cannot be launched (missing file, wrong architecture…).
    public static func start(_ spec: ProcessSpec) throws -> RunningProcess {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.environment = spec.environment
        process.currentDirectoryURL = spec.workingDirectory
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let (lines, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
        let state = OSAllocatedUnfairLock(initialState: State())
        let reader = pipe.fileHandleForReading

        @Sendable func finishOutput() {
            let remainder: String? = state.withLock { state in
                guard !state.outputFinished else { return nil }
                state.outputFinished = true
                defer { state.buffer.removeAll() }
                return state.buffer.isEmpty ? "" : Self.decode(state.buffer)
            }
            guard let remainder else { return }
            reader.readabilityHandler = nil
            if !remainder.isEmpty { continuation.yield(remainder) }
            continuation.finish()
        }

        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                finishOutput()
                return
            }
            let complete: [String] = state.withLock { state in
                guard !state.outputFinished else { return [] }
                state.buffer.append(chunk)
                var lines: [String] = []
                while let newline = state.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                    lines.append(Self.decode(state.buffer[state.buffer.startIndex..<newline]))
                    state.buffer.removeSubrange(state.buffer.startIndex...newline)
                }
                return lines
            }
            for line in complete { continuation.yield(line) }
        }

        process.terminationHandler = { process in
            let status = process.terminationStatus
            let waiters = state.withLock { state in
                state.exitStatus = status
                defer { state.waiters.removeAll() }
                return state.waiters
            }
            for waiter in waiters { waiter.resume(returning: status) }
            Task {
                try? await Task.sleep(for: outputGracePeriod)
                finishOutput()
            }
        }

        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            continuation.finish()
            throw error
        }
        return RunningProcess(process: process, lines: lines, state: state)
    }

    /// Waits for the process to exit and returns its status.
    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            let status: Int32? = state.withLock { state in
                if let status = state.exitStatus { return status }
                state.waiters.append(continuation)
                return nil
            }
            if let status { continuation.resume(returning: status) }
        }
    }

    /// Sends `SIGTERM`.
    public func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// Windows console programs (`reg`, `cmd`…) write in the OEM code page, which is 850 for
    /// Spanish and other Western European locales. Wine's own messages are UTF-8 (ASCII).
    static let consoleEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatin1.rawValue)))

    static func decode(_ bytes: Data) -> String {
        var line =
            String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: consoleEncoding)
            ?? String(decoding: bytes, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }
}

/// Runs short helper commands (wineboot, winecfg, tar…) and collects their output.
public enum ProcessRunner {
    public static func run(_ spec: ProcessSpec) async throws -> ProcessResult {
        let process = try RunningProcess.start(spec)
        return try await withTaskCancellationHandler {
            var lines: [String] = []
            for await line in process.lines { lines.append(line) }
            let status = await process.waitForExit()
            try Task.checkCancellation()
            return ProcessResult(status: status, lines: lines)
        } onCancel: {
            process.terminate()
        }
    }
}
