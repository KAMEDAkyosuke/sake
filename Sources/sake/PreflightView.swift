import SakeKit
import SwiftUI

struct PreflightView: View {
    let requirements: [Requirement]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
