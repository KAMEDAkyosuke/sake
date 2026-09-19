import SakeKit
import SwiftUI

enum D3DMetalStatus: Equatable {
    case working(phase: String, item: String)
    case installed(version: String?)
    case alreadyInstalled(version: String?)
    case failed(String)
}

struct D3DMetalView: View {
    let status: D3DMetalStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("d3dmetal")
                    .font(.callout.monospaced())
                    .frame(width: 190, alignment: .leading)

                switch status {
                case .none:
                    Text("waiting")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                case .working(let phase, let item):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(item)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                case .installed(let version):
                    Text(version.map { "installed — \($0)" } ?? "installed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .alreadyInstalled(let version):
                    Text(version.map { "already installed — \($0)" } ?? "already installed")
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
}
