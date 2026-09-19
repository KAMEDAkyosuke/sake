import SakeKit
import SwiftUI

enum ImportStatus: Equatable {
    case working(entry: String)
    case nothingToImport
    case imported(count: Int, bytes: Int64)
    case failed(String)
}

struct ImportView: View {
    let sources: [CrossOverBottle]
    @Binding var selection: CrossOverBottle?
    let candidates: [String]
    let status: ImportStatus?
    /// Why the button is off, as a sentence. `nil` when it is on.
    let blockedBy: String?
    let isImporting: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import")
                        .font(.title2.weight(.semibold))
                    Text("""
                        A game you already installed in CrossOver, cloned into this bottle. \
                        It costs no disk space, and CrossOver's copy is only read.
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isImporting {
                    Button("Stop", action: stop)
                } else {
                    Button("Import", action: start)
                        .disabled(blockedBy != nil || candidates.isEmpty)
                }
            }

            if !sources.isEmpty {
                Picker("From", selection: $selection) {
                    ForEach(sources) { source in
                        Text(source.name).tag(CrossOverBottle?.some(source))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .disabled(isImporting)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(selection?.name ?? "no bottle")
                    .font(.callout.monospaced())
                    .frame(width: 190, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)

                switch status {
                case .none:
                    if let blockedBy {
                        Text(blockedBy)
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(candidates, id: \.self) { candidate in
                                Text(candidate)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tertiary)
                            }
                            if candidates.isEmpty {
                                Text("nothing here this bottle does not already have")
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                case .working(let entry):
                    VStack(alignment: .leading, spacing: 2) {
                        Text("cloning")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(entry)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                case .nothingToImport:
                    Text("nothing here this bottle does not already have")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .imported(let count, let bytes):
                    Text("""
                        imported \(count) — \(bytes.formatted(.byteCount(style: .file))), \
                        sharing every block with CrossOver's copy
                        """)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
