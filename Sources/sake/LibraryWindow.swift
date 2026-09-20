import SakeKit
import SwiftUI

/// What the sidebar can be on: a bottle itself, or one of the titles in it.
///
/// A bottle has to be selectable in its own right or a new one — which has nothing in it —
/// would be a heading with no way to reach what it can do.
enum LibrarySelection: Hashable {
    case bottle(String)
    case title(bottle: String, id: String)
}

/// The window for using sake rather than setting it up: the bottles and what is in them on
/// the left, and one of those at a time on the right.
struct LibraryWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(model.bottles, id: \.name) { bottle in
                    Section {
                        rows(for: bottle)
                    } header: {
                        heading(for: bottle)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Menu {
                    Button("New Bottle…") { model.isCreatingBottle = true }
                    Button("Import from CrossOver…") {
                        model.beginImport(into: model.selectedBottle ?? Bottle.defaultName)
                    }
                    .disabled(model.bottles.isEmpty)
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
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
        .sheet(isPresented: $model.isCreatingBottle) { NewBottleSheet().environment(model) }
        .task {
            await model.check()
            // First run lands here with nothing built, so the wizard opens itself rather
            // than leaving an empty window and a button to find.
            if !isReady { openWindow(id: WindowID.setup) }
        }
    }

    /// A `List`'s selection only reaches its rows, so a selected heading is drawn rather
    /// than highlighted.
    private func heading(for bottle: Bottle) -> some View {
        let isSelected = model.selection == .bottle(bottle.name)
        return Button {
            model.selection = .bottle(bottle.name)
        } label: {
            Text(bottle.name)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rows(for bottle: Bottle) -> some View {
        let titles = model.titles[bottle.name] ?? []
        if titles.isEmpty {
            // Without this the section is a heading with nothing under it, which reads as
            // a rendering fault rather than as an empty bottle.
            Text("nothing here yet")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .selectionDisabled()
        } else {
            ForEach(titles) { title in
                Label(title.name, systemImage: "gamecontroller")
                    .tag(LibrarySelection.title(bottle: bottle.name, id: title.id))
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .title(let bottle, _):
            if let title = model.selectedTitle {
                TitleDetail(
                    title: title,
                    status: model.titleStatus,
                    isRunning: model.runningTitle == RunningTitle(bottle: bottle, title: title),
                    blockedBy: model.blocker(for: title, in: bottle),
                    play: { model.startTitle(title, in: bottle) },
                    stop: model.stopTitle
                )
            }
        case .bottle(let name):
            if let bottle = model.bottles.first(where: { $0.name == name }) {
                BottleDetail(
                    bottle: bottle,
                    titles: model.titles[name] ?? [],
                    importCandidates: name == model.importTarget ? model.importCandidates.count : nil,
                    importing: { model.beginImport(into: name) }
                )
            }
        case .none:
            empty
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text(model.bottles.isEmpty ? "No bottles yet" : "Nothing selected")
                .font(.title3)
                .foregroundStyle(.secondary)

            if !isReady {
                Text("sake is not set up yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isReady: Bool {
        model.setup.isComplete(machineIsReady: model.machineIsReady)
    }
}
