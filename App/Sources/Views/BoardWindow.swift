import AppKit
import KanbanCore
import SwiftUI

/// The main window's content.
struct BoardWindow: View {
    @Environment(BoardStore.self) private var store
    @Environment(BoardUI.self) private var ui
    @Environment(DragController.self) private var drag
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var boardFocused: Bool

    var body: some View {
        @Bindable var ui = ui

        VStack(spacing: 0) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
            if let banner = store.banner {
                BannerView(banner: banner) { withAnimation(Motion.spring(reduceMotion)) { store.dismissBanner() } }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            BoardCanvas()
        }
        .background(Palette.background)
        .frame(minWidth: 620, minHeight: 440)
        .navigationTitle(AppInfo.name)
        .toolbar { BoardToolbar(ui: ui, store: store) }
        .toolbarBackground(Palette.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .overlay(alignment: .bottom) {
            if let toast = ui.toast {
                ToastView(toast: toast) { ui.undoToast(in: store, animation: Motion.spring(reduceMotion)) }
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .focusable()
        .focused($boardFocused)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat], action: handleKey)
        .onChange(of: ui.boardFocusRequest) { boardFocused = true }
        .onChange(of: store.lastChange) { _, change in ui.handle(change, in: store) }
        .onChange(of: reduceMotion, initial: true) { _, reduce in drag.reduceMotion = reduce }
        .sheet(isPresented: $ui.showArchive) { ArchiveView() }
        .onAppear {
            boardFocused = true
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { DebugDemo.apply(ui: ui, store: store) }
            #endif
        }
    }

    /// Board shortcuts, active when no text field has focus.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Typing in a field (composer, search, editor) is never a board shortcut.
        if (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder is NSTextView { return .ignored }
        guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
        let arrows: [KeyEquivalent] = [.upArrow, .downArrow, .leftArrow, .rightArrow]
        if press.phase == .repeat && !arrows.contains(press.key) { return .ignored }
        let animation = Motion.spring(reduceMotion)
        switch press.key {
        case .upArrow: ui.moveSelection(.up, in: store)
        case .downArrow: ui.moveSelection(.down, in: store)
        case .leftArrow: ui.moveSelection(.left, in: store)
        case .rightArrow: ui.moveSelection(.right, in: store)
        case .space, .return:
            guard let id = ui.selectedCardID, store.card(id) != nil else { return .ignored }
            ui.openEditor(id)
        case .delete, .deleteForward:
            guard let id = ui.selectedCardID, !store.isReadOnly else { return .ignored }
            ui.delete(id, in: store, animation: animation)
        case .escape:
            if ui.isFiltering {
                ui.clearFilter()
            } else if ui.selectedCardID != nil {
                ui.select(nil)
            } else {
                return .ignored
            }
        default:
            return .ignored
        }
        return .handled
    }
}

enum AppInfo {
    static let name = "Kanban Board"
}

/// The four columns, separated by hairlines. Each is at least 240 pt wide and
/// they share the width equally; below that the board scrolls sideways.
struct BoardCanvas: View {
    @Environment(BoardUI.self) private var ui
    @Environment(DragController.self) private var drag

    private let padding: CGFloat = 10
    static let minimumColumnWidth: CGFloat = 240

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = max(Self.minimumColumnWidth, (geometry.size.width - padding * 2 - 3) / 4)
            let contentWidth = columnWidth * 4 + 3 + padding * 2
            let scrolls = contentWidth > geometry.size.width + 0.5

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Column.allCases) { column in
                        if column != .todo {
                            Rectangle().fill(Palette.hairline).frame(width: 1)
                        }
                        ColumnView(column: column)
                            .frame(width: columnWidth)
                    }
                }
                .padding(.horizontal, padding)
                .frame(height: geometry.size.height)
                .background(ScrollViewProbe { drag.boardScrollView = $0 })
            }
            .scrollIndicators(scrolls ? .automatic : .never)
            .scrollDisabled(!scrolls)
        }
        .coordinateSpace(.named(BoardSpace.viewport))
        .background(ViewportProbe { drag.viewportView = $0 })
        .onGeometryChange(for: CGSize.self) { $0.size } action: { drag.viewportSize = $0 }
        .overlay { DragOverlay() }
        .contentShape(Rectangle())
        .onTapGesture { ui.backgroundTapped() }
    }
}

/// The card that follows the pointer: lifted out of its panel as a standalone
/// card (scale 1.02, no tilt), then fading as the real row lands, or springing home.
struct DragOverlay: View {
    @Environment(DragController.self) private var drag
    @Environment(BoardStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if drag.isActive, let card = drag.card {
            let size = drag.cardSize
            LiftedCardView(card: card, today: store.today)
                .frame(width: size.width)
                .scaleEffect(drag.lifted && !reduceMotion ? 1.02 : 1)
                .opacity(drag.overlayOpacity)
                .position(x: drag.overlayOrigin.x + size.width / 2, y: drag.overlayOrigin.y + size.height / 2)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A flat bar under the toolbar: restored-from-backup (medium tones) or
/// read-only (neutral).
struct BannerView: View {
    let banner: BoardBanner
    let onDismiss: () -> Void

    private var tone: Priority { banner.kind == .readOnly ? .none : .medium }

    var body: some View {
        HStack(spacing: 10) {
            Text(banner.message)
                .font(.system(size: 12.5))
                .foregroundStyle(banner.kind == .readOnly ? Palette.textSecondary : Palette.textPrimary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.ink(tone))
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .background(Palette.fill(tone))
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }
}

/// "Deleted '…' · Undo" in an inverted capsule.
struct ToastView: View {
    let toast: BoardUI.DeleteToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(toast.message)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("·").opacity(0.6)
            Button("Undo", action: onUndo)
                .buttonStyle(.plain)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.buttonPrimaryText)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Capsule().fill(Palette.buttonPrimary))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Undo", onUndo)
    }
}

/// Title · summary · | · search · archive · New Task.
struct BoardToolbar: ToolbarContent {
    let ui: BoardUI
    let store: BoardStore

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text(AppInfo.name)
                .font(.serif(16, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .padding(.leading, 6)
                .fixedSize()
        }
        .plainToolbarItem()

        FlexibleToolbarSpace()

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 14) {
                if store.settings.showSummaryStrip {
                    ToolbarSummary(store: store)
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 16)
                }
                SearchField(ui: ui)
                Button {
                    ui.showArchive = true
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Archive (⇧⌘A)")
                .accessibilityLabel("Archive")
                Button {
                    ui.openComposer(.todo)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        Text("New Task")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.buttonPrimaryText)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.buttonPrimary))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New task (⌘N)")
                .disabled(store.isReadOnly)
            }
            .padding(.trailing, 8)
        }
        .plainToolbarItem()
    }
}

/// Pushes what follows to the trailing edge (macOS 26 lays toolbar items out
/// from the leading edge otherwise).
private struct FlexibleToolbarSpace: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        }
    }
}

private extension ToolbarContent {
    /// No Liquid Glass capsule behind custom toolbar views (macOS 26+).
    @ToolbarContentBuilder
    func plainToolbarItem() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// "14 tasks · 4 in progress · 2 done this week · 14% complete".
private struct ToolbarSummary: View {
    let store: BoardStore

    var body: some View {
        let stats = store.stats
        HStack(spacing: 14) {
            item(stats.total, stats.total == 1 ? "task" : "tasks")
            item(stats.inProgress, "in progress", warning: store.isOverWIPLimit)
            item(stats.doneThisWeek, "done this week")
            item("\(Int((stats.fractionComplete * 100).rounded()))%", "complete")
        }
        .font(.system(size: 12))
        .fixedSize()
    }

    private func item(_ value: Int, _ label: String, warning: Bool = false) -> some View {
        item("\(value)", label, warning: warning)
    }

    private func item(_ value: String, _ label: String, warning: Bool = false) -> some View {
        (Text(value).fontWeight(.semibold).foregroundStyle(warning ? Palette.wipWarning : Palette.textPrimary)
            + Text(" \(label)").foregroundStyle(Palette.textTertiary))
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityElement(children: .combine)
    }
}

/// Always-visible search (⌘F focuses it, Esc clears).
private struct SearchField: View {
    @Bindable var ui: BoardUI
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
            if let category = ui.categoryFilter {
                Button { ui.categoryFilter = nil } label: {
                    HStack(spacing: 3) {
                        Text(category).lineLimit(1)
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Palette.field))
                }
                .buttonStyle(.plain)
                .help("Clear the category filter")
            }
            TextField("Search", text: $ui.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
                .onExitCommand { ui.clearFilter() }
            if ui.searchText.isEmpty && ui.categoryFilter == nil {
                Text("⌘F")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
            } else if !ui.searchText.isEmpty {
                Button { ui.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 180, height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.field))
        .onChange(of: ui.searchFocusRequest) { focused = true }
    }
}
