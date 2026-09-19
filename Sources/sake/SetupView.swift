import SakeKit
import SwiftUI

struct SetupView: View {
    @State private var requirements: [Requirement] = []
    @State private var isChecking = false
    @State private var sources: [String: SourceStatus] = [:]
    @State private var fetch: Task<Void, Never>?
    @State private var fetchGeneration = 0

    var body: some View {
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

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity,
               minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .task { await check() }
    }

    private var machineIsReady: Bool {
        !requirements.isEmpty && requirements.allSatisfy(\.status.isSatisfied)
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        requirements = await Preflight.run()
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
            if generation == fetchGeneration { fetch = nil }
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
}
