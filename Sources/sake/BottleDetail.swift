import SakeKit
import SwiftUI

/// One bottle, on its own. What is in it, and the way to put something in it — which is the
/// only thing a bottle just created can do.
struct BottleDetail: View {
    let bottle: Bottle
    let titles: [Title]
    /// How many things a CrossOver bottle has that this one does not, or `nil` when that
    /// has not been worked out for this bottle.
    let importCandidates: Int?
    let importing: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(bottle.name)
                    .font(.largeTitle.weight(.semibold))
                Text(bottle.url.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Import from CrossOver…", action: importing)
                .controlSize(.large)

            VStack(alignment: .leading, spacing: 4) {
                Text(counts)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let importCandidates, importCandidates > 0 {
                    Text("""
                        \(importCandidates) in a CrossOver bottle could come over, and \
                        cloning costs nothing.
                        """)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// syswow64 is here for the same reason the wizard shows it: it is empty on a prefix
    /// that looks complete, and nothing 32-bit runs then. See docs/runtime.md.
    private var counts: String {
        let files = bottle.systemFileCounts()
        let games = titles.isEmpty
            ? "nothing that can be started"
            : "\(titles.count) that can be started"
        return """
            \(games) — system32 \(files.system32.formatted()) / \
            syswow64 \(files.sysWoW64.formatted()) files
            """
    }
}
