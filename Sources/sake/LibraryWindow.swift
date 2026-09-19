import SakeKit
import SwiftUI

/// The window for using sake rather than setting it up: what is in the bottle on the left,
/// and one of them at a time on the right.
struct LibraryWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selectedTitle) {
                Section(Bottle.defaultName) {
                    ForEach(model.titles) { title in
                        Label(title.name, systemImage: "gamecontroller")
                            .tag(title.id)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.isImporting = true
                } label: {
                    Label("Import from CrossOver…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem {
                Button(isReady ? "Set Up…" : "Finish Setting Up…") {
                    openWindow(id: WindowID.setup)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 380)
        .sheet(isPresented: $model.isImporting) { ImportSheet().environment(model) }
        .task {
            await model.check()
            // First run lands here with nothing built, so the wizard opens itself rather
            // than leaving an empty window and a button to find.
            if !isReady { openWindow(id: WindowID.setup) }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let title = model.titles.first(where: { $0.id == model.selectedTitle }) {
            TitleDetail(
                title: title,
                status: model.titleStatus,
                isRunning: model.runningTitle == title,
                blockedBy: model.titleBlockedBy,
                play: { model.startTitle(title) },
                stop: model.stopTitle
            )
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(model.titles.isEmpty ? "Nothing in this bottle yet" : "Nothing selected")
                .font(.title3)
                .foregroundStyle(.secondary)

            if model.titles.isEmpty {
                if !isReady {
                    Text("sake is not set up yet.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                } else if !model.importCandidates.isEmpty {
                    Text("""
                        There \(model.importCandidates.count == 1 ? "is" : "are") \
                        \(model.importCandidates.count) in a CrossOver bottle that could \
                        come over, and cloning costs nothing.
                        """)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                    Button("Import from CrossOver…") { model.isImporting = true }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isReady: Bool {
        model.setup.isComplete(machineIsReady: model.machineIsReady)
    }
}
