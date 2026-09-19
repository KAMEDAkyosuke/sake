import SakeKit
import SwiftUI

enum ImportStatus: Equatable {
    case working(entry: String)
    case nothingToImport
    case imported(count: Int, bytes: Int64)
    case failed(String)
}

/// Choosing what to bring over, on top of the library rather than inside it.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 16) {
            Text("Import from CrossOver")
                .font(.title2.weight(.semibold))

            if model.importSources.count > 1 {
                Picker("From", selection: $model.importSource) {
                    ForEach(model.importSources) { source in
                        Text(source.name).tag(CrossOverBottle?.some(source))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(model.importing.isRunning)
                .onChange(of: model.importSource) { model.loadImportOffer() }
            } else if let only = model.importSources.first {
                Text(only.name)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }

            offer

            Text("""
                Cloned, not copied: what comes over shares its blocks with CrossOver's copy, \
                so it costs no disk space, and CrossOver's own install is only ever read.
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
                if model.importing.isRunning {
                    Button("Stop", action: model.stopImport)
                } else {
                    Button("Import", action: model.startImport)
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.importChoices.isEmpty)
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .task { model.loadImportOffer() }
    }

    @ViewBuilder
    private var offer: some View {
        if let blocked = model.importBlockedBy {
            Text(blocked)
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.importCandidates.isEmpty {
            Text("Nothing here this bottle does not already have.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.importCandidates, id: \.self) { candidate in
                    Toggle(isOn: choice(for: candidate)) {
                        HStack {
                            Text(candidate)
                                .font(.callout)
                            Spacer(minLength: 12)
                            // Measured after the list is on screen, so this fills in a
                            // moment later on a big source bottle rather than holding it up.
                            Text(model.importSizes[candidate].map {
                                $0.formatted(.byteCount(style: .file))
                            } ?? "…")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.importing.isRunning)
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.importStatus {
        case .working(let entry):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(entry.isEmpty ? "starting" : entry)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .imported(let count, let bytes):
            Text("imported \(count) — \(bytes.formatted(.byteCount(style: .file)))")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Text(reason)
                .font(.callout)
                .foregroundStyle(.orange)
                .lineLimit(2)
        case .nothingToImport, .none:
            EmptyView()
        }
    }

    private func choice(for candidate: String) -> Binding<Bool> {
        Binding(
            get: { model.importChoices.contains(candidate) },
            set: { wanted in
                if wanted { model.importChoices.insert(candidate) }
                else { model.importChoices.remove(candidate) }
            }
        )
    }
}
