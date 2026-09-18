import SwiftUI

@main
struct SakeApp: App {
    var body: some Scene {
        WindowGroup {
            PlaceholderView()
        }
        .windowResizability(.contentSize)
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wineglass")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("sake")
                .font(.largeTitle)
            Text("Nothing is implemented yet. See docs/roadmap.md.")
                .foregroundStyle(.secondary)
        }
        .padding(48)
        .frame(minWidth: 420, minHeight: 280)
    }
}
