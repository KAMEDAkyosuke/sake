import SakeKit
import SwiftUI

enum PrefixStatus: Equatable {
    case working(phase: String, line: String)
    case built
    case alreadyBuilt
    case failed(String)
}

struct PrefixView: View {
    let statuses: [String: PrefixStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(BuildRecipe.all) { recipe in
                PrefixRow(recipe: recipe, status: statuses[recipe.id])
            }
        }
    }
}

private struct PrefixRow: View {
    let recipe: BuildRecipe
    let status: PrefixStatus?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(recipe.componentID)
                .font(.callout.monospaced())
                .frame(width: 190, alignment: .leading)

            switch status {
            case .none:
                Text("waiting")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
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
            case .built:
                Text("built")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .alreadyBuilt:
                Text("already built")
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
