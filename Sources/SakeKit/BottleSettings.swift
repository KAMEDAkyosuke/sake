import Foundation

/// What is set for a whole bottle rather than for one title in it.
///
/// A setting belongs here when wineserver holds it: every process in the prefix talks to
/// the one server, so a value one title sets and the next program does not is a prefix
/// that refuses that program. See docs/runtime.md.
public struct BottleSettings: Codable, Sendable, Equatable {
    /// CrossOver's msync, `WINEMSYNC=1`. wineserver decides it when it starts, and a client
    /// that disagrees exits 1 during its own startup -- saying why only at `err`, which
    /// `WINEDEBUG=-all` hides. Measured on 2026-09-23.
    public var msync: Bool

    public init(msync: Bool = false) {
        self.msync = msync
    }

    /// Every field optional going in, for the reason `layout.md` gives about
    /// `sake-titles.json`: a field added later must not turn a file already on disk into
    /// one that does not decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        msync = try container.decodeIfPresent(Bool.self, forKey: .msync) ?? false
    }
}

extension Bottle {
    /// In the prefix, beside `sake-titles.json`, so that a rename carries it along and
    /// throwing the bottle away takes it too. See docs/layout.md.
    public var settingsURL: URL { url.appending(path: "sake-bottle.json") }

    /// The defaults when there is no file, or one that cannot be read.
    public var settings: BottleSettings {
        guard let data = try? Data(contentsOf: settingsURL) else { return BottleSettings() }
        return (try? JSONDecoder().decode(BottleSettings.self, from: data)) ?? BottleSettings()
    }

    /// Write `settings`, taking the bottle down first when they differ from what it has.
    ///
    /// Down first because what is already running was started under the old values: with
    /// msync changed, the wineserver left behind -- kept up by a Battle.net Agent nobody
    /// sees -- refuses every program started afterwards.
    public func change(
        to settings: BottleSettings, runner: ProcessRunner = ProcessRunner()
    ) async throws {
        guard settings != self.settings else { return }
        await takeDown(runner: runner)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }
}
