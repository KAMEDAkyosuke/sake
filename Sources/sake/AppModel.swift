import Observation
import SakeKit
import SwiftUI

/// A long operation that can be stopped and started again.
///
/// The generation is load-bearing: a stopped run finishes winding down after the next one
/// has started, and must not clear that one's handle.
@MainActor
@Observable
final class Run {
    private(set) var task: Task<Void, Never>?
    private var generation = 0

    var isRunning: Bool { task != nil }

    func start(_ body: @escaping @MainActor () async -> Void, then done: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        generation += 1
        let mine = generation
        task = Task {
            await body()
            if mine == generation {
                task = nil
                done()
            }
        }
    }

    func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }
}

/// Everything both windows show. The wizard and the library are two views of one machine's
/// state, so the state cannot belong to either of them.
@MainActor
@Observable
final class AppModel {
    let paths = Paths.default

    var requirements: [Requirement] = []
    var isChecking = false

    var sources: [String: SourceStatus] = [:]
    var prefix: [String: PrefixStatus] = [:]
    var wine: WineStatus?
    var d3dMetal: D3DMetalStatus?
    var bottle: BottleStatus?

    var importSources: [CrossOverBottle] = []
    var importSource: CrossOverBottle?
    var importCandidates: [String] = []
    var importChoices: Set<String> = []
    var importSizes: [String: Int64] = [:]
    var importStatus: ImportStatus?
    var importBlockedBy: String?
    var isImporting = false

    var titles: [Title] = []
    var selectedTitle: Title.ID?
    var runningTitle: Title?
    var titleStatus: TitleStatus?
    var titleBlockedBy: String?

    let fetching = Run()
    let building = Run()
    let buildingWine = Run()
    let installing = Run()
    let creating = Run()
    let importing = Run()
    let playing = Run()

    var machineIsReady: Bool {
        !requirements.isEmpty && requirements.allSatisfy(\.status.isSatisfied)
    }

    var setup: Setup { Setup(paths: paths) }

    func state(of step: SetupStep) -> StepState {
        setup.state(of: step, machineIsReady: machineIsReady)
    }

    func isRunning(_ step: SetupStep) -> Bool {
        switch step {
        case .machine: isChecking
        case .sources: fetching.isRunning
        case .prefix: building.isRunning
        case .wine: buildingWine.isRunning
        case .d3dMetal: installing.isRunning
        case .bottle: creating.isRunning
        }
    }

    func start(_ step: SetupStep) {
        switch step {
        case .machine:
            Task { await check() }
        case .sources:
            fetching.start({ for await e in SourceFetcher(paths: self.paths).fetch() { self.apply(e) } },
                           then: survey)
        case .prefix:
            building.start({ for await e in PrefixBuilder(paths: self.paths).build() { self.apply(e) } },
                           then: survey)
        case .wine:
            buildingWine.start({ for await e in WineBuilder(paths: self.paths).build() { self.apply(e) } },
                               then: survey)
        case .d3dMetal:
            installing.start({ for await e in D3DMetalInstaller(paths: self.paths).install() { self.apply(e) } },
                             then: survey)
        case .bottle:
            creating.start({ for await e in BottleBuilder(paths: self.paths).create() { self.apply(e) } },
                           then: survey)
        }
    }

    func stop(_ step: SetupStep) {
        switch step {
        case .machine: break
        case .sources: fetching.stop()
        case .prefix: building.stop()
        case .wine: buildingWine.stop()
        case .d3dMetal: installing.stop()
        case .bottle: creating.stop()
        }
    }

    func check() async {
        isChecking = true
        defer { isChecking = false }
        requirements = await Preflight.run()
        survey()
    }

    /// What is already on disk. Without this the rows all read "waiting" until a run is
    /// started, however much of the work is already done.
    func survey() {
        for component in Component.all where component.isUnpacked(in: paths) {
            sources[component.id] = .inPlace
        }
        for recipe in BuildRecipe.all where recipe.isBuilt(in: paths.engine) {
            prefix[recipe.id] = .alreadyBuilt
        }
        if WineBuilder(paths: paths).isBuilt { wine = .alreadyBuilt }

        let installer = D3DMetalInstaller(paths: paths)
        if installer.isInstalled {
            d3dMetal = .alreadyInstalled(version: installer.installedVersion())
        }

        let bottles = BottleBuilder(paths: paths)
        if bottles.bottle.exists {
            let counts = bottles.bottle.systemFileCounts()
            bottle = .alreadyCreated(system32: counts.system32, sysWoW64: counts.sysWoW64)
        }

        importSources = CrossOverBottle.available()
        if importSource == nil || !importSources.contains(where: { $0 == importSource }) {
            importSource = importSources.first
        }
        if let source = importSource {
            let importer = BottleImporter(paths: paths, source: source)
            importCandidates = importer.candidates()
            importBlockedBy = importer.missingPrerequisite
        } else {
            importCandidates = []
            importBlockedBy = "No CrossOver bottle to import from."
        }

        titles = Title.installed(in: bottles.bottle)
        if selectedTitle == nil || !titles.contains(where: { $0.id == selectedTitle }) {
            selectedTitle = titles.first?.id
        }
        titleBlockedBy = titles.isEmpty
            ? "Nothing that can be started is in this bottle yet."
            : TitleLauncher(paths: paths, title: titles[0]).missingPrerequisite
    }

    /// What the import sheet offers. The names are a pair of directory listings and come
    /// back at once; the sizes walk the source bottle, so they arrive afterwards.
    func loadImportOffer() {
        guard let source = importSource else { return }
        let importer = BottleImporter(paths: paths, source: source)
        importCandidates = importer.candidates()
        importBlockedBy = importer.missingPrerequisite
        importChoices = Set(importCandidates)
        importSizes = [:]
        Task { importSizes = await importer.sizes(of: importCandidates) }
    }

    private func apply(_ event: FetchEvent) {
        switch event {
        case .alreadyInPlace(let component):
            sources[component.id] = .inPlace
        case .started(let component):
            sources[component.id] = .downloading(fraction: nil)
        case .progress(let component, let bytes, let total):
            sources[component.id] = .downloading(fraction: total.map { Double(bytes) / Double($0) })
        case .downloaded(let component, let verified):
            sources[component.id] = .unpacking(verified: verified)
        case .unpacked(let component):
            if case .unpacking(let verified) = sources[component.id] {
                sources[component.id] = .ready(verified: verified)
            } else {
                sources[component.id] = .ready(verified: component.sha256 != nil)
            }
        case .failed(let component, let reason):
            sources[component.id] = .failed(reason)
        case .finished:
            break
        }
    }

    private func apply(_ event: BuildEvent) {
        switch event {
        case .alreadyBuilt(let recipe):
            prefix[recipe.id] = .alreadyBuilt
        case .started(let recipe):
            prefix[recipe.id] = .working(phase: "starting", line: "")
        case .phase(let recipe, let phase):
            prefix[recipe.id] = .working(phase: phase.rawValue, line: "")
        case .output(let recipe, let line):
            if case .working(let phase, _) = prefix[recipe.id] {
                prefix[recipe.id] = .working(phase: phase, line: line)
            }
        case .installed(let recipe):
            prefix[recipe.id] = .built
        case .failed(let recipe, let reason, _):
            prefix[recipe.id] = .failed(reason)
        case .finished:
            break
        }
    }

    private func apply(_ event: WineEvent) {
        switch event {
        case .alreadyBuilt: wine = .alreadyBuilt
        case .started: wine = .working(phase: "starting", line: "")
        case .phase(let phase): wine = .working(phase: phase.rawValue, line: "")
        case .output(let line):
            if case .working(let phase, _) = wine { wine = .working(phase: phase, line: line) }
        case .installed(let version): wine = .built(version: version)
        case .failed(let reason, _): wine = .failed(reason)
        case .finished: break
        }
    }

    private func apply(_ event: D3DMetalEvent) {
        switch event {
        case .alreadyInstalled(let version): d3dMetal = .alreadyInstalled(version: version)
        case .started: d3dMetal = .working(phase: "starting", item: "")
        case .phase(let phase): d3dMetal = .working(phase: phase.rawValue, item: "")
        case .placed(let item):
            if case .working(let phase, _) = d3dMetal { d3dMetal = .working(phase: phase, item: item) }
        case .installed(let version): d3dMetal = .installed(version: version)
        case .failed(let reason): d3dMetal = .failed(reason)
        case .finished: break
        }
    }

    private func apply(_ event: BottleEvent) {
        switch event {
        case .alreadyCreated(let system32, let sysWoW64):
            bottle = .alreadyCreated(system32: system32, sysWoW64: sysWoW64)
        case .started: bottle = .working(phase: "starting", line: "")
        case .phase(let phase): bottle = .working(phase: phase.rawValue, line: "")
        case .output(let line):
            if case .working(let phase, _) = bottle { bottle = .working(phase: phase, line: line) }
        case .created(let system32, let sysWoW64):
            bottle = .created(system32: system32, sysWoW64: sysWoW64)
        case .failed(let reason, _): bottle = .failed(reason)
        case .finished: break
        }
    }

    func startImport() {
        guard let source = importSource else { return }
        let chosen = Array(importChoices)
        importing.start({
            for await e in BottleImporter(paths: self.paths, source: source).run(chosen) {
                self.apply(e)
            }
        }) {
            self.survey()
            self.loadImportOffer()
        }
    }

    func stopImport() { importing.stop() }

    private func apply(_ event: ImportEvent) {
        switch event {
        case .nothingToImport: importStatus = .nothingToImport
        case .started: importStatus = .working(entry: "")
        case .cloning(let entry): importStatus = .working(entry: entry)
        case .cloned: break
        case .failed(let reason, _): importStatus = .failed(reason)
        case .finished(let cloned, let bytes):
            // A run that failed has already said so, and its count would read as success.
            if case .failed = importStatus {} else if cloned > 0 {
                importStatus = .imported(count: cloned, bytes: bytes)
            }
        }
    }

    func startTitle(_ title: Title) {
        runningTitle = title
        titleStatus = .starting
        playing.start({
            for await e in TitleLauncher(paths: self.paths, title: title).launch() { self.apply(e) }
        }) {
            self.runningTitle = nil
            self.survey()
        }
    }

    /// Cancelling reaches `wine` and nothing else, so the bottle is taken down explicitly
    /// and then looked at again rather than assumed down. See docs/runtime.md.
    func stopTitle() {
        guard let title = runningTitle else { return }
        playing.stop()
        Task {
            let left = await TitleLauncher(paths: paths, title: title).stop()
            titleStatus = .stopped(left: left.count)
            runningTitle = nil
            survey()
        }
    }

    private func apply(_ event: LaunchEvent) {
        switch event {
        case .started: titleStatus = .starting
        case .output(let line): titleStatus = .running(line: line)
        case .exited(let status): titleStatus = .exited(status: status)
        case .failed(let reason, _): titleStatus = .failed(reason)
        case .finished: break
        }
    }
}
