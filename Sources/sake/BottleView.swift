import SakeKit
import SwiftUI

enum BottleStatus: Equatable {
    case working(phase: String, line: String)
    case created(system32: Int, sysWoW64: Int)
    case alreadyCreated(system32: Int, sysWoW64: Int)
    case failed(String)
}

struct BottleView: View {
    let name: String
    let status: BottleStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name)
                    .font(.callout.monospaced())
                    .frame(width: 190, alignment: .leading)

                switch status {
                case .none:
                    Text("waiting")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                case .working(let phase, let line):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                case .created(let system32, let sysWoW64):
                    Text("created — \(Self.files(system32, sysWoW64))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .alreadyCreated(let system32, let sysWoW64):
                    Text("already created — \(Self.files(system32, sysWoW64))")
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

    /// Both counts, because syswow64 is the one that says whether a 32-bit application can
    /// run at all, and it is empty on a prefix that looks otherwise complete.
    private static func files(_ system32: Int, _ sysWoW64: Int) -> String {
        "system32 \(system32.formatted()) / syswow64 \(sysWoW64.formatted()) files"
    }
}
