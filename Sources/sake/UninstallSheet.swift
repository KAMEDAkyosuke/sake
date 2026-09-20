import SakeKit
import SwiftUI

enum UninstallStatus: Equatable {
    case working(String)
    case done(count: Int)
    case failed(String)
}

/// Taking everything away, on top of the library.
///
/// One button and no second confirmation: the list above it is the confirmation, and what
/// it describes goes to the Trash rather than away.
struct UninstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Uninstall sake")
                .font(.title2.weight(.semibold))

            if model.uninstallItems.isEmpty {
                Text("There is nothing of sake's left on this disk.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.uninstallItems) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.name)
                            Spacer(minLength: 20)
                            Text(size(of: item))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }

            Text("""
                \(roots) go to the Trash, so this can be undone until you empty it — and \
                emptying it returns less than the total above, because a game imported from \
                CrossOver shares its blocks with CrossOver's own copy. Your own copy of \
                Apple's D3DMetal goes with the downloads.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sake.app itself stays where it is. Drag it to the Trash when you are done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                status
                Spacer(minLength: 20)
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if model.uninstalling.isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Move Everything to the Trash", role: .destructive) {
                        model.uninstall()
                    }
                    .disabled(model.uninstallItems.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { model.loadUninstallOffer() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.uninstallStatus {
        case .none:
            EmptyView()
        case .working(let what):
            Text(what)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .done:
            VStack(alignment: .leading, spacing: 2) {
                Text("Moved to the Trash.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(model.uninstallLanded, id: \.self) { landed in
                    Text(abbreviated(landed))
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        case .failed(let reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func size(of item: Uninstaller.Item) -> String {
        model.uninstallSizes[item.id]?.formatted(.byteCount(style: .file)) ?? "…"
    }

    private var roots: String {
        Uninstaller(paths: model.paths).roots
            .map(abbreviated)
            .formatted()
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}
