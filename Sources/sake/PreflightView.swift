import SakeKit
import SwiftUI

struct PreflightView: View {
    let requirements: [Requirement]
    let isChecking: Bool
    let recheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This Mac")
                        .font(.title2.weight(.semibold))
                    Text("What decides whether sake can build anything here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isChecking {
                    ProgressView().controlSize(.small)
                }
                Button("Check Again", action: recheck)
                    .disabled(isChecking)
            }

            ForEach(requirements) { requirement in
                RequirementRow(requirement: requirement)
            }
        }
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
