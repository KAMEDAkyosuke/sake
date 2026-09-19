import SakeKit
import SwiftUI

struct PreflightView: View {
    @State private var requirements: [Requirement] = []
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before sake builds anything")
                    .font(.title2.weight(.semibold))
                Text("Nothing has been downloaded or built yet. These are what decide whether it can be.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(requirements) { requirement in
                    RequirementRow(requirement: requirement)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if isChecking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Check Again") {
                    Task { await check() }
                }
                .disabled(isChecking)
            }
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 560, maxWidth: .infinity,
               minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .task { await check() }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        requirements = await Preflight.run()
    }
}

private struct RequirementRow: View {
    let requirement: Requirement

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: requirement.status.isSatisfied
                  ? "checkmark.circle.fill"
                  : "exclamationmark.triangle.fill")
                .foregroundStyle(requirement.status.isSatisfied ? Color.green : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(requirement.title)
                    .font(.headline)
                switch requirement.status {
                case .satisfied(let detail):
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .actionNeeded(let problem, let remedy):
                    Text(problem)
                        .font(.callout)
                    Text(remedy)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }
}
