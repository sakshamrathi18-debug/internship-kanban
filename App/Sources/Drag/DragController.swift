import AppKit
import KanbanCore
import Observation
import SwiftUI

/// In-window drag and drop for cards.
///
/// A `DragGesture` on the row only *starts* a drag. From then on an AppKit
/// local event monitor drives it (pointer moves, mouse-up, Esc), so the drag
/// can't get stuck even if the lazy stack recycles the source row mid-drag.
/// A 60 Hz timer handles auto-scroll near edges and doubles as a safety net:
/// if the mouse button is up but we missed the event, it drops.
///
/// Targets are a priority panel in a column plus a position in it. Dropping
/// into a different panel changes the card's priority (one undo step).
@MainActor
@Observable
final class DragController {
    enum Phase: Equatable {
        case idle
        case dragging
        /// The lifted copy fading out while the real row springs into place.
        case settling
        /// Animating back to where it started (Esc, or dropped outside).
        case returning
    }

    struct DropTarget: Equatable {
        let column: Column
        /// The panel. Always `.none` for Done, which is one panel.
        let priority: Priority
        /// Position among the panel's other cards.
        let index: Int
        let isOriginalSpot: Bool
    }

    struct PanelKey: Hashable {
        let column: Column
        let priority: Priority
    }

    // Observed by the columns (these change rarely during a drag).
    private(set) var phase: Phase = .idle
    private(set) var card: TaskCard?
    private(set) var target: DropTarget?
    private(set) var cardSize: CGSize = .zero

    // Observed only by the floating card.
    private(set) var overlayOrigin: CGPoint = .zero
    private(set) var lifted = false
    private(set) var overlayOpacity: Double = 1

    // Geometry, written by the views. Not observed.
    @ObservationIgnored private var cardFrameRecords: [UUID: (column: Column, frame: CGRect)] = [:]
    /// Frames of each panel's pieces (header, rows, line, placeholder).
    @ObservationIgnored private var segmentFrames: [PanelKey: [String: CGRect]] = [:]

    func reportSegment(_ frame: CGRect, of key: PanelKey, id: String) {
        segmentFrames[key, default: [:]][id] = frame
    }

    func forgetSegment(of key: PanelKey, id: String) {
        segmentFrames[key]?[id] = nil
    }

    /// A panel's bounds: the union of its visible pieces.
    var panelFrames: [PanelKey: CGRect] {
        segmentFrames.compactMapValues { pieces in
            pieces.isEmpty ? nil : pieces.values.reduce(CGRect.null) { $0.union($1) }
        }
    }
    @ObservationIgnored var columnFrames: [Column: CGRect] = [:]
    @ObservationIgnored var bodyFrames: [Column: CGRect] = [:]
    @ObservationIgnored var viewportSize: CGSize = .zero
    @ObservationIgnored weak var viewportView: NSView?
    @ObservationIgnored var columnScrollViews: [Column: WeakScrollView] = [:]
    @ObservationIgnored weak var boardScrollView: NSScrollView?

    @ObservationIgnored weak var store: BoardStore?
    @ObservationIgnored weak var ui: BoardUI?
    @ObservationIgnored var reduceMotion = false

    @ObservationIgnored private var grabOffset: CGSize = .zero
    @ObservationIgnored private var pointer: CGPoint = .zero
    @ObservationIgnored private var sourceIndex = 0
    @ObservationIgnored private var initialFrame: CGRect?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var cursorPushed = false
    @ObservationIgnored private var lastPointerEvent = Date()

    private static let edgeZone: CGFloat = 48
    private static let maxScrollStep: CGFloat = 18

    var isActive: Bool { phase != .idle }

    /// The panel a card is drawn in (Done is one panel).
    static func panel(of card: TaskCard) -> Priority {
        card.column == .done ? .none : card.priority
    }

    // MARK: - Geometry from the views

    func reportFrame(_ frame: CGRect, for card: TaskCard) {
        cardFrameRecords[card.id] = (card.column, frame)
    }

    func forgetFrame(for card: TaskCard) {
        if cardFrameRecords[card.id]?.column == card.column { cardFrameRecords[card.id] = nil }
    }

    func frame(of card: TaskCard) -> CGRect? {
        guard let record = cardFrameRecords[card.id], record.column == card.column else { return nil }
        return record.frame
    }

    // MARK: - Gesture entry points

    func gestureChanged(card: TaskCard, start: CGPoint, location: CGPoint) {
        if phase == .idle { debugLog("gesture start \(card.title.prefix(12)) at \(start)") }
        switch phase {
        case .idle:
            begin(card: card, start: start, location: location)
        case .dragging where monitor == nil:
            pointerMoved(to: location)
        default:
            break
        }
    }

    func gestureEnded() {
        if phase == .dragging { drop() }
    }

    // MARK: - Lifecycle

    private func begin(card: TaskCard, start: CGPoint, location: CGPoint) {
        guard let store, !store.isReadOnly, let frame = frame(of: card) else { return }
        ui?.editingCardID = nil
        store.endEditing()
        ui?.select(card.id)

        self.card = card
        sourceIndex = store.board.group(Self.panel(of: card), in: card.column).firstIndex { $0.id == card.id } ?? 0
        cardSize = frame.size
        initialFrame = frame
        grabOffset = CGSize(width: start.x - frame.minX, height: start.y - frame.minY)
        pointer = location
        lastPointerEvent = Date()
        overlayOrigin = origin(for: location)
        overlayOpacity = 1
        phase = .dragging
        target = computeTarget()
        withAnimation(Motion.spring(reduceMotion)) { lifted = true }
        installTracking()
    }

    private func pointerMoved(to point: CGPoint) {
        guard phase == .dragging else { return }
        pointer = point
        overlayOrigin = origin(for: point)
        refreshTarget()
    }

    private func refreshTarget() {
        let newTarget = computeTarget()
        guard newTarget != target else { return }
        withAnimation(Motion.spring(reduceMotion)) { target = newTarget }
    }

    private func drop() {
        guard phase == .dragging else { return }
        debugLog("drop pointer=\(pointer) target=\(String(describing: target))")
        removeTracking()
        guard let card, let target, !target.isOriginalSpot else {
            returnToOrigin()
            return
        }
        // The real row springs into its new place while the lifted copy fades.
        phase = .settling
        ui?.suppressArrival(of: card.id)
        withAnimation(Motion.spring(reduceMotion)) {
            _ = store?.move(card.id, to: target.column, priority: target.column == .done ? nil : target.priority, index: target.index)
            self.target = nil
        }
        withAnimation(.easeOut(duration: 0.18), completionCriteria: .logicallyComplete) {
            overlayOpacity = 0
            lifted = false
        } completion: {
            MainActor.assumeIsolated { self.reset() }
        }
        ui?.focusBoard()
    }

    /// Esc, a drop outside the board, or the app losing focus.
    func cancel() {
        guard phase == .dragging else { return }
        removeTracking()
        returnToOrigin()
    }

    private func returnToOrigin() {
        guard let card else { reset(); return }
        phase = .returning
        let destination = frame(of: card)?.origin ?? initialFrame?.origin
        withAnimation(Motion.settle(reduceMotion), completionCriteria: .logicallyComplete) {
            if let destination { overlayOrigin = destination }
            lifted = false
            target = nil
        } completion: {
            MainActor.assumeIsolated { self.reset() }
        }
        ui?.focusBoard()
    }

    private func reset() {
        removeTracking()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            phase = .idle
            card = nil
            target = nil
            lifted = false
            overlayOpacity = 1
        }
        initialFrame = nil
    }

    // MARK: - Hit testing

    private func origin(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - grabOffset.width, y: point.y - grabOffset.height)
    }

    private func computeTarget() -> DropTarget? {
        guard let card, let store else { return nil }
        let viewport = CGRect(origin: .zero, size: viewportSize).insetBy(dx: -8, dy: -8)
        guard viewportSize == .zero || viewport.contains(pointer) else { return nil }

        let candidates = Column.allCases.compactMap { column in columnFrames[column].map { (column, $0) } }
        guard let (column, _) = candidates.min(by: {
            distance(pointer.x, $0.1.minX, $0.1.maxX) < distance(pointer.x, $1.1.minX, $1.1.maxX)
        }) else { return nil }

        // Which panel: the one under the pointer, else the nearest one vertically.
        let panels: [Priority] = column == .done ? [.none] : Priority.boardOrder
        let allPanels = panelFrames
        let framed = panels.compactMap { p in allPanels[PanelKey(column: column, priority: p)].map { (p, $0) } }
        let priority = framed.min(by: {
            distance(pointer.y, $0.1.minY, $0.1.maxY) < distance(pointer.y, $1.1.minY, $1.1.maxY)
        })?.0 ?? (column == .done ? .none : card.priority)

        let others = store.board.group(priority, in: column).filter { $0.id != card.id }
        var index = others.count
        var lastKnownAbove: Int?
        for (i, other) in others.enumerated() {
            guard let frame = frame(of: other) else { continue }
            if pointer.y < frame.midY {
                index = i
                lastKnownAbove = nil
                break
            }
            lastKnownAbove = i
        }
        if let above = lastKnownAbove { index = above + 1 }
        let original = column == card.column && priority == Self.panel(of: card) && index == sourceIndex
        return DropTarget(column: column, priority: priority, index: index, isOriginalSpot: original)
    }

    private func distance(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        if value < low { return low - value }
        if value > high { return value - high }
        return 0
    }

    // MARK: - Tracking (event monitor, timer, cursor)

    private func installTracking() {
        removeTracking()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .rightMouseDown]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSCursor.closedHand.push()
        cursorPushed = true
    }

    private func removeTracking() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }

    /// Returns true to swallow the event.
    private func handle(_ event: NSEvent) -> Bool {
        guard phase == .dragging else { return false }
        switch event.type {
        case .leftMouseDragged:
            lastPointerEvent = Date()
            if let point = viewportPoint(for: event) { pointerMoved(to: point) }
            return false
        case .leftMouseUp:
            if let point = viewportPoint(for: event) { pointerMoved(to: point) }
            drop()
            return false
        case .keyDown:
            if event.keyCode == 53 { cancel() } // Esc
            return true
        case .rightMouseDown:
            cancel()
            return true
        default:
            return false
        }
    }

    private func viewportPoint(for event: NSEvent) -> CGPoint? {
        guard let view = viewportView, event.window === view.window else { return nil }
        return view.convert(event.locationInWindow, from: nil)
    }

    private func tick() {
        guard phase == .dragging else { return }
        // Safety net: never leave a drag hanging if the mouse-up went missing.
        if NSEvent.pressedMouseButtons & 1 == 0, Date().timeIntervalSince(lastPointerEvent) > 0.4 {
            drop()
            return
        }
        if autoscroll() { refreshTarget() }
    }

    private func autoscroll() -> Bool {
        var scrolled = false
        if let column = target?.column ?? card?.column, let body = bodyFrames[column],
           let scrollView = columnScrollViews[column]?.view,
           pointer.x >= body.minX - 12, pointer.x <= body.maxX + 12 {
            if pointer.y < body.minY + Self.edgeZone, pointer.y > body.minY - 40 {
                scrolled = scrollView.nudge(by: -step(depth: body.minY + Self.edgeZone - pointer.y), vertical: true) || scrolled
            } else if pointer.y > body.maxY - Self.edgeZone, pointer.y < body.maxY + 40 {
                scrolled = scrollView.nudge(by: step(depth: pointer.y - (body.maxY - Self.edgeZone)), vertical: true) || scrolled
            }
        }
        if let board = boardScrollView, viewportSize.width > 0 {
            if pointer.x < Self.edgeZone {
                scrolled = board.nudge(by: -step(depth: Self.edgeZone - pointer.x), vertical: false) || scrolled
            } else if pointer.x > viewportSize.width - Self.edgeZone {
                scrolled = board.nudge(by: step(depth: pointer.x - (viewportSize.width - Self.edgeZone)), vertical: false) || scrolled
            }
        }
        return scrolled
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["KANBAN_DRAG_LOG"] != nil {
            FileHandle.standardError.write(Data("[drag] \(message())\n".utf8))
        }
        #endif
    }

    private func step(depth: CGFloat) -> CGFloat {
        let t = min(max(depth / Self.edgeZone, 0), 1.4)
        return max(2, Self.maxScrollStep * t * t)
    }
}
