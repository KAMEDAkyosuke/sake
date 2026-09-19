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
    /// Why the button is off, as a sentence. `nil` when it is on.
    let blockedBy: String?
    let isInstalling: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("D3DMetal")
                        .font(.title2.weight(.semibold))
                    Text("""
                        Apple's DirectX 12 layer. sake may not ship it or download it for \
                        you — mount the Game Porting Toolkit and sake copies it out.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isInstalling {
                    Button("Stop", action: stop)
                } else {
                    Button("Install", action: start)
                        .disabled(blockedBy != nil)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("d3dmetal")
                    .font(.callout.monospaced())
                    .frame(width: 190, alignment: .leading)

                switch status {
                case .none:
                    Text(blockedBy ?? "waiting")
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
