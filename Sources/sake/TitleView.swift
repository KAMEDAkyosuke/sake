import SakeKit
import SwiftUI

enum TitleStatus: Equatable {
    case starting
    case running(line: String)
    case exited(status: Int32)
    case stopped(left: Int)
    case failed(String)
}

struct TitleView: View {
    let titles: [Title]
    let running: Title?
    let status: TitleStatus?
    /// Why the buttons are off, as a sentence. `nil` when they are on.
    let blockedBy: String?
    let start: (Title) -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Play")
                    .font(.title2.weight(.semibold))
                Text("""
                    What is in the bottle and can be started. Closing the window does not \
                    stop a bottle — Stop does, by killing wineserver.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if titles.isEmpty {
                Text(blockedBy ?? "nothing in this bottle can be started yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(titles) { title in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title.name)
                        .font(.callout.monospaced())
                        .frame(width: 190, alignment: .leading)

                    if running == title {
                        line(for: status)
                    } else {
                        Text(blockedBy ?? "ready")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if running == title {
                        Button("Stop", action: stop)
                    } else {
                        Button("Play") { start(title) }
                            .disabled(blockedBy != nil || running != nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func line(for status: TitleStatus?) -> some View {
        switch status {
        case .none, .starting:
            Text("starting")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .running(let line):
            VStack(alignment: .leading, spacing: 2) {
                Text("running")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(line)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .exited(let status):
            Text(status == 0 ? "exited" : "exited — status \(status)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .stopped(let left):
            // Saying what is left rather than claiming success: `wineserver -k` exits 0
            // whether or not it killed anything.
            Text(left == 0 ? "stopped — nothing left running" : "stopped — \(left) still running")
                .font(.callout)
                .foregroundStyle(left == 0 ? Color.secondary : Color.orange)
        case .failed(let reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
