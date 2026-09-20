import SakeKit
import SwiftUI
import UniformTypeIdentifiers

enum InstallStatus: Equatable {
    case working(line: String)
    case exited(status: Int32)
    case stopped(left: Int)
    case failed(String)
}

/// Running a game's own installer inside a bottle.
struct InstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var isChoosing = false

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Install from an Installer")
                .font(.title2.weight(.semibold))

            Text("Into \(model.installTarget)")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Choose Installer…") { isChoosing = true }
                    .disabled(model.installingGame.isRunning)
                if let installer = model.installer {
                    Text(installer.lastPathComponent)
                        .font(.callout.monospaced())
                        .truncationMode(.middle)
                        .lineLimit(1)
                } else {
                    Text("No installer chosen")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Text("""
                The installer is yours to download — sake does not fetch one for you, the \
                same line it draws around Apple's toolkit. Point it at the .exe or .msi you \
                already have and it runs in this bottle, with a window of its own.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                status
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if model.installingGame.isRunning {
                    Button("Stop", action: model.stopInstall)
                } else {
                    if case .exited = model.installStatus {
                        Button("Add a Title…", action: model.addTitleAfterInstall)
                    }
                    Button("Install", action: model.startInstall)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.installer == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .fileImporter(
            isPresented: $isChoosing,
            allowedContentTypes: InstallSheet.installerTypes
        ) { result in
            if case .success(let url) = result { model.installer = url }
        }
    }

    /// `.exe` and `.msi` are not types the system declares, so they are made from their
    /// extensions; `data` keeps the panel usable if a future macOS stops recognising one.
    private static let installerTypes: [UTType] = {
        let declared = InstallerRunner.extensions.compactMap { UTType(filenameExtension: $0) }
        return declared.isEmpty ? [.data] : declared
    }()

    @ViewBuilder
    private var status: some View {
        switch model.installStatus {
        case .working(let line):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(line.isEmpty ? "Starting…" : line)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
        case .exited(let status):
            // An installer's exit status says it closed, not that it installed anything:
            // what decides that is whether the game shows up in the library.
            Text(status == 0 ? "The installer closed." : "The installer exited with \(status).")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .stopped(let left):
            Text(left == 0 ? "Stopped." : "Stopped; \(left) still running.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }
}
