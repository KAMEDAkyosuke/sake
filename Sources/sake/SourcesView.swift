import SakeKit
import SwiftUI

enum SourceStatus: Equatable {
    case downloading(fraction: Double?)
    case unpacking(verified: Bool)
    case ready(verified: Bool)
    case inPlace
    case failed(String)
}

struct SourcesView: View {
    let statuses: [String: SourceStatus]
    let isFetching: Bool
    let canStart: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sources")
                        .font(.title2.weight(.semibold))
                    Text("Downloaded, checked against a known hash, and unpacked. Nothing is built yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isFetching {
                    Button("Stop", action: stop)
                } else {
                    Button("Download", action: start)
                        .disabled(!canStart)
                }
            }

            ForEach(Component.all) { component in
                SourceRow(component: component, status: statuses[component.id])
            }
        }
    }
}

private struct SourceRow: View {
    let component: Component
    let status: SourceStatus?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(component.id) \(component.version)")
                .font(.callout.monospaced())
                .frame(width: 190, alignment: .leading)

            switch status {
            case .none:
                Text("waiting")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            case .downloading(let fraction):
                if let fraction {
                    ProgressView(value: fraction).frame(maxWidth: 160)
                } else {
                    ProgressView().controlSize(.small)
                }
            case .unpacking:
                Text("unpacking")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .ready(let verified):
                Text(verified ? "ready, hash matched" : "ready, no known hash to check against")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .inPlace:
                Text("already unpacked")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
