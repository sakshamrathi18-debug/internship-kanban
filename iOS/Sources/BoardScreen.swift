import KanbanCore
import SwiftUI

/// The whole board on a phone: the system tab bar with one tab per column,
/// each showing its count, and each column in its own navigation stack with
/// "+" and "…" in the top bar.
struct BoardScreen: View {
    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var ui = ui
        TabView(selection: $ui.column) {
            ForEach(Column.allCases) { column in
                Tab(value: column) {
                    ColumnScreen(column: column)
                } label: {
                    TabLabel(column: column, count: store.stats.count(for: column))
                }
            }
        }
        .overlay(alignment: .bottom) { toastLayer }
        .animation(Motion.spring(reduceMotion), value: ui.toast)
        .sheet(item: $ui.editor) { item in
            PhoneCardEditor(cardID: item.id)
        }
        .sheet(isPresented: $ui.showComposer) {
            PhoneComposer(column: ui.column)
        }
        .sheet(isPresented: $ui.showArchive) { PhoneArchive() }
        .sheet(isPresented: $ui.showSettings) { PhoneSettings() }
        .tint(Palette.appAccent)
    }

    private var toastLayer: some View {
        VStack {
            if let toast = ui.toast {
                PhoneToast(toast: toast) {
                    ui.undoDelete(in: store, animation: Motion.spring(reduceMotion))
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 96)
    }
}

/// One column's tab: its panels, the column's name and status in the top
/// bar, "+" to add a task here, and "…" for Undo, Archive and Settings.
struct ColumnScreen: View {
    let column: Column

    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let banner = store.banner {
                    PhoneBanner(banner: banner) { store.dismissBanner() }
                }
                ColumnPage(column: column)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(column.title)
            .navigationBarTitleDisplayMode(.inline)
            .columnSubtitle(store.settings.showSummaryStrip ? subtitle : "")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        ui.column = column
                        ui.showComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(store.isReadOnly)
                    .accessibilityLabel("New Task")
                    .accessibilityHint("Adds a task to \(column.title)")
                    BoardMenu()
                }
            }
        }
    }

    /// "6 tasks", "4 of 3 · over your limit", "2 this week · 14% done".
    private var subtitle: String {
        let stats = store.stats
        let count = stats.count(for: column)
        switch column {
        case .todo:
            return count == 1 ? "1 task" : "\(count) tasks"
        case .inProgress:
            guard let limit = store.settings.wipLimit else { return "\(count) in progress" }
            return store.isOverWIPLimit ? "\(count) of \(limit) · over your limit" : "\(count) of \(limit)"
        case .onHold:
            return count == 0 ? "Nothing waiting" : "\(count) waiting on someone"
        case .done:
            return "\(stats.doneThisWeek) this week · \(Int((stats.fractionComplete * 100).rounded()))% done"
        }
    }
}

/// "…": Undo, Redo, Archive, Settings.
struct BoardMenu: View {
    @Environment(BoardStore.self) private var store
    @Environment(PhoneUI.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Menu {
            Button {
                withAnimation(Motion.spring(reduceMotion)) { store.undo() }
            } label: {
                Label(store.undoState.canUndo ? "Undo \(store.undoState.undoName)" : "Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(!store.undoState.canUndo)
            Button {
                withAnimation(Motion.spring(reduceMotion)) { store.redo() }
            } label: {
                Label(store.undoState.canRedo ? "Redo \(store.undoState.redoName)" : "Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(!store.undoState.canRedo)
            Divider()
            Button { ui.showArchive = true } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button { ui.showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }
}

/// A column's tab: its count as the icon (a circled number, filled when
/// selected), and its name underneath.
private struct TabLabel: View {
    let column: Column
    let count: Int

    var body: some View {
        // SF Symbols has circled numbers up to 50.
        if count <= 50 {
            Label(column.title, systemImage: "\(count).circle")
        } else {
            Label("\(column.title) \(count)", systemImage: "circle.grid.2x2")
        }
    }
}

private extension View {
    /// The column's status under its title (iOS 26 and later).
    @ViewBuilder
    func columnSubtitle(_ text: String) -> some View {
        if #available(iOS 26.0, *), !text.isEmpty {
            navigationSubtitle(text)
        } else {
            self
        }
    }
}

/// Restored-from-backup / read-only notices, as on the Mac.
struct PhoneBanner: View {
    let banner: BoardBanner
    let onDismiss: () -> Void

    private var tone: Priority { banner.kind == .readOnly ? .none : .medium }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(banner.message)
                .font(.system(size: 14))
                .foregroundStyle(banner.kind == .readOnly ? Palette.textSecondary : Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Dismiss", action: onDismiss)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.ink(tone))
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.vertical, 10)
        .background(Palette.fill(tone))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// "Deleted '…' · Undo" in an inverted capsule.
struct PhoneToast: View {
    let toast: PhoneUI.DeleteToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(toast.message)
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
        }
        .font(.system(size: 15))
        .foregroundStyle(Palette.buttonPrimaryText)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Capsule().fill(Palette.buttonPrimary.opacity(0.94)))
        .padding(.horizontal, PhoneMetrics.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
    }
}
