import Foundation
import Testing

@testable import SakeKit

private let shell = URL(filePath: "/bin/sh")

@Test func keepsStandardOutputAndStandardErrorApart() async throws {
    let result = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", "echo out; echo err >&2"])
    )

    #expect(result.exitStatus == 0)
    #expect(result.succeeded)
    #expect(result.standardOutput == "out\n")
    #expect(result.standardError == "err\n")
}

@Test func reportsANonZeroExitInsteadOfThrowing() async throws {
    let result = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", "exit 3"])
    )

    #expect(result.exitStatus == 3)
    #expect(!result.succeeded)
}

@Test func throwsWhenTheExecutableDoesNotExist() async {
    let missing = URL(filePath: "/usr/bin/there-is-no-such-tool")

    await #expect(throws: CommandError.self) {
        try await ProcessRunner().run(Command(executable: missing))
    }
}

/// Both pipes are filled well past the 64 KiB buffer. Draining them one after the other
/// rather than at once hangs here instead of finishing.
@Test func doesNotDeadlockWhenBothStreamsOverflowTheirBuffer() async throws {
    let script = "i=0; while [ $i -lt 20000 ]; do echo \"out $i\"; echo \"err $i\" >&2; i=$((i+1)); done"
    let result = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", script])
    )

    #expect(result.exitStatus == 0)
    #expect(result.standardOutput.utf8.count > 65536)
    #expect(result.standardError.utf8.count > 65536)
    #expect(result.standardOutput.hasSuffix("out 19999\n"))
    #expect(result.standardError.hasSuffix("err 19999\n"))
}

/// What a `make -j` build actually does: one stream goes quiet for a long time while the
/// other fills its pipe. A reader that serialises the two streams hangs here.
@Test func doesNotDeadlockWhenStandardOutputIsQuietWhileStandardErrorOverflows() async throws {
    let script = "i=0; while [ $i -lt 20000 ]; do echo \"err $i\" >&2; i=$((i+1)); done; echo done"
    let result = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", script])
    )

    #expect(result.standardOutput == "done\n")
    #expect(result.standardError.utf8.count > 65536)
}

@Test func doesNotDeadlockWhenStandardErrorIsTheQuietOne() async throws {
    let script = "i=0; while [ $i -lt 20000 ]; do echo \"out $i\"; i=$((i+1)); done; echo done >&2"
    let result = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", script])
    )

    #expect(result.standardError == "done\n")
    #expect(result.standardOutput.utf8.count > 65536)
}

@Test func streamsLinesAsTheyArrive() async throws {
    let collected = Collector()
    _ = try await ProcessRunner().run(
        Command(executable: shell, arguments: ["-c", "echo one; echo two >&2; echo three"]),
        onOutput: { collected.append($0) }
    )

    let lines = collected.lines
    #expect(lines.contains(.standardOutput("one")))
    #expect(lines.contains(.standardError("two")))
    #expect(lines.contains(.standardOutput("three")))

    let outputOrder = lines.compactMap { line -> String? in
        if case .standardOutput(let text) = line { text } else { nil }
    }
    #expect(outputOrder == ["one", "three"])
}

@Test func cancellationKillsTheChild() async throws {
    let task = Task {
        try await ProcessRunner().run(
            Command(executable: URL(filePath: "/bin/sleep"), arguments: ["120"])
        )
    }
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()

    await #expect(throws: CancellationError.self) {
        try await task.value
    }
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: Rosetta.runtimePath)))
func runsTranslatedWhenAskedFor_x86_64() async throws {
    let result = try await ProcessRunner().run(
        Command(
            executable: URL(filePath: "/usr/bin/uname"),
            arguments: ["-m"],
            architecture: .x86_64
        )
    )

    #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "x86_64")
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [OutputLine] = []

    var lines: [OutputLine] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: OutputLine) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(line)
    }
}
