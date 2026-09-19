import Foundation

public enum Architecture: Sendable, Equatable {
    case native

    /// Run translated, through `arch -x86_64`.
    ///
    /// Builds only. A build has to be translated so that the host tools it generates and
    /// then executes (winebuild, widl, wrc, makedep) are x86_64 like the target. A *wine
    /// run* must never be wrapped: wine's binaries are x86_64 already, and `arch` is a
    /// hardened system binary, so exec'ing it strips every `DYLD_*` variable from the
    /// environment. See docs/wine-build.md.
    case x86_64
}

public struct Command: Sendable, Equatable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]?
    public var workingDirectory: URL?
    public var architecture: Architecture

    public init(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        architecture: Architecture = .native
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.architecture = architecture
    }
}

public enum OutputLine: Sendable, Equatable {
    case standardOutput(String)
    case standardError(String)

    public var text: String {
        switch self {
        case .standardOutput(let text), .standardError(let text): text
        }
    }
}

public struct CommandResult: Sendable, Equatable {
    public let exitStatus: Int32
    public let standardOutput: String
    public let standardError: String

    public var succeeded: Bool { exitStatus == 0 }
}

public enum CommandError: Error, Equatable, LocalizedError {
    case launchFailed(executable: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let executable, let reason):
            "Could not run \(executable.path): \(reason)"
        }
    }
}

public struct ProcessRunner: Sendable {
    public init() {}

    /// Run `command` to completion, streaming each line to `onOutput` as it arrives.
    ///
    /// A non-zero exit is a result, not an error: it is reported in
    /// ``CommandResult/exitStatus``. Only a failure to launch, or cancellation, throws.
    ///
    /// Output is captured line by line, so a final line the child left without a newline
    /// gains one.
    ///
    /// Cancelling sends SIGTERM. A child that ignores it is not forced.
    public func run(
        _ command: Command,
        onOutput: (@Sendable (OutputLine) -> Void)? = nil
    ) async throws -> CommandResult {
        try Task.checkCancellation()

        let box = ProcessBox()
        let process = box.process

        switch command.architecture {
        case .native:
            process.executableURL = command.executable
            process.arguments = command.arguments
        case .x86_64:
            process.executableURL = URL(filePath: "/usr/bin/arch")
            process.arguments = ["-x86_64", command.executable.path] + command.arguments
        }
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        process.standardInput = FileHandle.nullDevice

        let (terminated, markTerminated) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { _ in markTerminated.finish() }

        // The two drains below run concurrently, so without this a caller's closure would be
        // called from two threads at once.
        let deliver = SerialDelivery(onOutput)

        do {
            try process.run()
        } catch {
            throw CommandError.launchFailed(
                executable: command.executable,
                reason: error.localizedDescription
            )
        }

        return try await withTaskCancellationHandler {
            // Drain both pipes at once. Reading one to EOF before starting on the other
            // deadlocks as soon as the child fills the second pipe's 64 KiB buffer, and a
            // wine build fills both.
            async let out = Self.drain(standardOutput, wrap: OutputLine.standardOutput, to: deliver)
            async let err = Self.drain(standardError, wrap: OutputLine.standardError, to: deliver)
            let (outText, errText) = await (out, err)

            for await _ in terminated {}

            if Task.isCancelled { throw CancellationError() }
            return CommandResult(
                exitStatus: process.terminationStatus,
                standardOutput: outText,
                standardError: errText
            )
        } onCancel: {
            box.terminate()
        }
    }

    /// Not `FileHandle.bytes`: every AsyncBytes iterator in the process shares one serial
    /// queue and does a blocking `read(2)` on it, so draining a stream that has gone quiet
    /// stops the other stream from being drained at all, and the child then blocks once its
    /// 64 KiB fills. A readability handler gets a queue per handle. Measured against a
    /// `make -j10` that sat at 0% CPU for 30 minutes, 2026-09-19.
    private static func drain(
        _ pipe: Pipe,
        wrap: @Sendable @escaping (String) -> OutputLine,
        to deliver: SerialDelivery
    ) async -> String {
        var text = ""
        var carry: [UInt8] = []

        func emit(_ bytes: ArraySlice<UInt8>) {
            var line = String(decoding: bytes, as: UTF8.self)
            if line.hasSuffix("\r") { line.removeLast() }
            text += line
            text += "\n"
            deliver(wrap(line))
        }

        for await chunk in readableChunks(of: pipe) {
            carry.append(contentsOf: chunk)
            while let newline = carry.firstIndex(of: UInt8(ascii: "\n")) {
                emit(carry[..<newline])
                carry.removeFirst(newline + 1)
            }
        }
        if !carry.isEmpty { emit(carry[...]) }

        return text
    }

    private static func readableChunks(of pipe: Pipe) -> AsyncStream<Data> {
        AsyncStream { continuation in
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in handle.readabilityHandler = nil }
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}

private final class SerialDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private let onOutput: (@Sendable (OutputLine) -> Void)?

    init(_ onOutput: (@Sendable (OutputLine) -> Void)?) {
        self.onOutput = onOutput
    }

    func callAsFunction(_ line: OutputLine) {
        guard let onOutput else { return }
        lock.lock()
        defer { lock.unlock() }
        onOutput(line)
    }
}
