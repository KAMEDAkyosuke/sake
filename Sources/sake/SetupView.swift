import SakeKit
import SwiftUI

struct SetupView: View {
    @State private var requirements: [Requirement] = []
    @State private var isChecking = false
    @State private var sources: [String: SourceStatus] = [:]
    @State private var fetch: Task<Void, Never>?
    @State private var fetchGeneration = 0
    @State private var prefix: [String: PrefixStatus] = [:]
    @State private var build: Task<Void, Never>?
    @State private var buildGeneration = 0
    @State private var wine: WineStatus?
    @State private var wineBlockedBy: String?
    @State private var wineBuild: Task<Void, Never>?
    @State private var wineGeneration = 0
    @State private var d3dMetal: D3DMetalStatus?
    @State private var d3dMetalBlockedBy: String?
    @State private var d3dMetalInstall: Task<Void, Never>?
    @State private var d3dMetalGeneration = 0
    @State private var bottle: BottleStatus?
    @State private var bottleBlockedBy: String?
    @State private var bottleCreate: Task<Void, Never>?
    @State private var bottleGeneration = 0
    @State private var importSources: [CrossOverBottle] = []
    @State private var importSource: CrossOverBottle?
    @State private var importCandidates: [String] = []
    @State private var importStatus: ImportStatus?
    @State private var importBlockedBy: String?
    @State private var importRun: Task<Void, Never>?
    @State private var importGeneration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreflightView(requirements: requirements, isChecking: isChecking) {
                    Task { await check() }
                }

                Divider()

                SourcesView(
                    statuses: sources,
                    isFetching: fetch != nil,
                    canStart: machineIsReady,
                    start: startFetching,
                    stop: stopFetching
                )

                Divider()

                PrefixView(
                    statuses: prefix,
                    isBuilding: build != nil,
                    canStart: machineIsReady,
                    start: startBuilding,
                    stop: stopBuilding
                )

                Divider()

                WineView(
                    status: wine,
                    blockedBy: wineBlockedBy,
                    isBuilding: wineBuild != nil,
                    start: startWine,
                    stop: stopWine
                )

                Divider()

                D3DMetalView(
                    status: d3dMetal,
                    blockedBy: d3dMetalBlockedBy,
                    isInstalling: d3dMetalInstall != nil,
                    start: startD3DMetal,
                    stop: stopD3DMetal
                )

                Divider()

                BottleView(
                    name: Bottle.defaultName,
                    status: bottle,
                    blockedBy: bottleBlockedBy,
                    isCreating: bottleCreate != nil,
                    start: startBottle,
                    stop: stopBottle
                )

                Divider()

                ImportView(
                    sources: importSources,
                    selection: $importSource,
                    candidates: importCandidates,
                    status: importStatus,
                    blockedBy: importBlockedBy,
                    isImporting: importRun != nil,
                    start: startImport,
                    stop: stopImport
                )
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 480, idealWidth: 620, maxWidth: .infinity,
               minHeight: 360, maxHeight: .infinity)
        .task { await check() }
    }

    private var machineIsReady: Bool {
        !requirements.isEmpty && requirements.allSatisfy(\.status.isSatisfied)
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        requirements = await Preflight.run()
        survey()
    }

    /// What is already on disk. Without this the rows all read "waiting" until a run is
    /// started, however much of the work is already done.
    private func survey() {
        let paths = Paths.default
        for component in Component.all where component.isUnpacked(in: paths) {
            sources[component.id] = .inPlace
        }
        let prefixURL = PrefixBuilder(paths: paths).prefix
        for recipe in BuildRecipe.all where recipe.isBuilt(in: prefixURL) {
            prefix[recipe.id] = .alreadyBuilt
        }

        let builder = WineBuilder(paths: paths)
        if builder.isBuilt { wine = .alreadyBuilt }
        wineBlockedBy = machineIsReady
            ? builder.missingPrerequisite
            : "This Mac is not ready yet."

        let installer = D3DMetalInstaller(paths: paths)
        if installer.isInstalled {
            d3dMetal = .alreadyInstalled(version: installer.installedVersion())
        }
        d3dMetalBlockedBy = machineIsReady
            ? installer.missingPrerequisite
            : "This Mac is not ready yet."

        let bottles = BottleBuilder(paths: paths)
        if bottles.bottle.exists {
            let counts = bottles.bottle.systemFileCounts()
            bottle = .alreadyCreated(system32: counts.system32, sysWoW64: counts.sysWoW64)
        }
        bottleBlockedBy = machineIsReady
            ? bottles.missingPrerequisite
            : "This Mac is not ready yet."

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
    }

    private func startFetching() {
        guard fetch == nil else { return }
        fetchGeneration += 1
        let generation = fetchGeneration
        fetch = Task {
            for await event in SourceFetcher().fetch() {
                apply(event)
            }
            // A stopped run finishes winding down after the next one has started, and must
            // not clear that one's handle.
            if generation == fetchGeneration {
                fetch = nil
                survey()
            }
        }
    }

    private func stopFetching() {
        fetchGeneration += 1
        fetch?.cancel()
        fetch = nil
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

    private func startBuilding() {
        guard build == nil else { return }
        buildGeneration += 1
        let generation = buildGeneration
        build = Task {
            for await event in PrefixBuilder().build() {
                apply(event)
            }
            if generation == buildGeneration {
                build = nil
                survey()
            }
        }
    }

    private func stopBuilding() {
        buildGeneration += 1
        build?.cancel()
        build = nil
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

    private func startWine() {
        guard wineBuild == nil else { return }
        wineGeneration += 1
        let generation = wineGeneration
        wineBuild = Task {
            for await event in WineBuilder().build() {
                apply(event)
            }
            if generation == wineGeneration {
                wineBuild = nil
                survey()
            }
        }
    }

    private func stopWine() {
        wineGeneration += 1
        wineBuild?.cancel()
        wineBuild = nil
    }

    private func apply(_ event: WineEvent) {
        switch event {
        case .alreadyBuilt:
            wine = .alreadyBuilt
        case .started:
            wine = .working(phase: "starting", line: "")
        case .phase(let phase):
            wine = .working(phase: phase.rawValue, line: "")
        case .output(let line):
            if case .working(let phase, _) = wine {
                wine = .working(phase: phase, line: line)
            }
        case .installed(let version):
            wine = .built(version: version)
        case .failed(let reason, _):
            wine = .failed(reason)
        case .finished:
            break
        }
    }

    private func startD3DMetal() {
        guard d3dMetalInstall == nil else { return }
        d3dMetalGeneration += 1
        let generation = d3dMetalGeneration
        d3dMetalInstall = Task {
            for await event in D3DMetalInstaller().install() {
                apply(event)
            }
            if generation == d3dMetalGeneration {
                d3dMetalInstall = nil
                survey()
            }
        }
    }

    private func stopD3DMetal() {
        d3dMetalGeneration += 1
        d3dMetalInstall?.cancel()
        d3dMetalInstall = nil
    }

    private func apply(_ event: D3DMetalEvent) {
        switch event {
        case .alreadyInstalled(let version):
            d3dMetal = .alreadyInstalled(version: version)
        case .started:
            d3dMetal = .working(phase: "starting", item: "")
        case .phase(let phase):
            d3dMetal = .working(phase: phase.rawValue, item: "")
        case .placed(let item):
            if case .working(let phase, _) = d3dMetal {
                d3dMetal = .working(phase: phase, item: item)
            }
        case .installed(let version):
            d3dMetal = .installed(version: version)
        case .failed(let reason):
            d3dMetal = .failed(reason)
        case .finished:
            break
        }
    }

    private func startBottle() {
        guard bottleCreate == nil else { return }
        bottleGeneration += 1
        let generation = bottleGeneration
        bottleCreate = Task {
            for await event in BottleBuilder().create() {
                apply(event)
            }
            if generation == bottleGeneration {
                bottleCreate = nil
                survey()
            }
        }
    }

    private func stopBottle() {
        bottleGeneration += 1
        bottleCreate?.cancel()
        bottleCreate = nil
    }

    private func apply(_ event: BottleEvent) {
        switch event {
        case .alreadyCreated(let system32, let sysWoW64):
            bottle = .alreadyCreated(system32: system32, sysWoW64: sysWoW64)
        case .started:
            bottle = .working(phase: "starting", line: "")
        case .phase(let phase):
            bottle = .working(phase: phase.rawValue, line: "")
        case .output(let line):
            if case .working(let phase, _) = bottle {
                bottle = .working(phase: phase, line: line)
            }
        case .created(let system32, let sysWoW64):
            bottle = .created(system32: system32, sysWoW64: sysWoW64)
        case .failed(let reason, _):
            bottle = .failed(reason)
        case .finished:
            break
        }
    }

    private func startImport() {
        guard importRun == nil, let source = importSource else { return }
        importGeneration += 1
        let generation = importGeneration
        importRun = Task {
            for await event in BottleImporter(source: source).run() {
                apply(event)
            }
            if generation == importGeneration {
                importRun = nil
                survey()
            }
        }
    }

    private func stopImport() {
        importGeneration += 1
        importRun?.cancel()
        importRun = nil
    }

    private func apply(_ event: ImportEvent) {
        switch event {
        case .nothingToImport:
            importStatus = .nothingToImport
        case .started:
            importStatus = .working(entry: "")
        case .cloning(let entry):
            importStatus = .working(entry: entry)
        case .cloned:
            break
        case .failed(let reason, _):
            importStatus = .failed(reason)
        case .finished(let cloned, let bytes):
            // A run that failed has already said so, and its count would read as success.
            if case .failed = importStatus {} else if cloned > 0 {
                importStatus = .imported(count: cloned, bytes: bytes)
            }
        }
    }
}
