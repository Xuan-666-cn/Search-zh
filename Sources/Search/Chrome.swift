import SwiftUI

// (Fork) Rearranging the row-end buttons. The order lives in Prefs
// .chromeOrder as a list of ids, not positions: the downloads door keeps
// its chosen slot while it's only on screen mid-download, a door turned
// off (bookmark) keeps its gap and returns where it left, and the pair
// up the left (navigationLeft) or beside the lights in the sidebar is a
// gap too. Both layouts draw from it — the strip's end and the sidebar's
// foot — each filtering to the parts it has.
//
// It first worked on the strip itself, Safari's way: Edit Layout on the
// doors and a drag there. But the strip under those doors is the window's
// own title bar — DragStrip (Stage.swift) moves the window on any press
// it keeps — and the window came along with the hand through three tries
// at yielding the region. So the arranging happens on a card hung under
// the row's end instead: no title bar over the page to fight, every door
// shown at once including the ones the row has no room for just now,
// and cells the card lays out itself, so the drag counts slots and can
// be applied to the row as it drops — visible behind the card, right
// where it changes.

/// The row's end buttons, and the person's order among them. Back and
/// forward travel as one door, apart from the reload — the three were
/// one block for as long as the row existed, and the card is the first
/// place anyone could put the reload on its own.
enum ChromePart: String, CaseIterable, Identifiable {
    case fetch, extensions, backforward, reload, bookmark

    var id: String { rawValue }

    /// The order it starts in; the card's Reset returns to it.
    static let standard: [ChromePart] = [.fetch, .extensions, .backforward, .reload, .bookmark]

    /// What the card calls it.
    var title: String {
        switch self {
        case .fetch: return "Downloads"
        case .extensions: return "Extensions"
        case .backforward: return "Back & Forward"
        case .reload: return "Refresh"
        case .bookmark: return "Bookmarks"
        }
    }

    /// Whether the row shows it as things stand. The ones it has no room
    /// for wait in the card dimmed, where a click is the show switch —
    /// the same one Settings has, two hands on one handle.
    @MainActor func shown(_ prefs: Preferences, _ fetches: Fetches) -> Bool {
        switch self {
        case .fetch: return FetchDoor.shows(fetches, prefs)
        case .extensions: return prefs.extensionsButton
        case .backforward: return !prefs.navigationLeft && !prefs.sidebar && prefs.backForwardButton
        case .reload: return !prefs.navigationLeft && !prefs.sidebar && prefs.reloadButton
        case .bookmark: return prefs.bookmarkButton
        }
    }

    /// Why the row is without it, for the card's tooltip: the mode, when
    /// the mode is what put it away, and the card's own click when that.
    @MainActor func away(_ prefs: Preferences) -> String {
        switch self {
        case .fetch: return "Nothing is downloading"
        case .extensions: return "Turned off in this layout"
        case .backforward, .reload:
            return prefs.sidebar || prefs.navigationLeft
                ? "In the sidebar they stand by the window's buttons; with them on the left, likewise"
                : "Turned off in this layout"
        case .bookmark: return "Turned off in Settings › Tabs"
        }
    }

    /// The door's own mark, or its like: back and forward are two small
    /// chevrons, since no single symbol says "the pair of them".
    @ViewBuilder var glyph: some View {
        if self == .backforward {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 8, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .medium))
            }
        } else {
            Image(systemName: self == .fetch ? "arrow.down.circle"
                : self == .extensions ? "puzzlepiece.extension"
                : self == .reload ? "arrow.clockwise" : "bookmark")
                .font(.system(size: 11, weight: .medium))
        }
    }
}

/// One door on the strip or in the foot: itself, and the way onto the
/// card that arranges them.
struct ChromeDoor<Inner: View>: View {
    @ObservedObject var browser: Browser
    let inner: () -> Inner

    init(browser: Browser, @ViewBuilder content: @escaping () -> Inner) {
        self.browser = browser
        self.inner = content
    }

    var body: some View {
        inner().contextMenu {
            Button("Edit Layout…") { withAnimation(Motion.glide) { browser.arrangingChrome = true } }
        }
    }
}

/// The card, hung under the row's end: all five doors in the chosen
/// order, dragged between slots, the row behind changing as they drop.
struct ChromeLayoutPanel: View {
    @ObservedObject var browser: Browser

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 4) {
                Text("Button Layout")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                Door(icon: "xmark", help: "Done   esc", act: { browser.arrangingChrome = false })
            }
            Text("Drag to rearrange · click to hide or show")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.muted)
            ChromeTray(browser: browser)
            Button("Reset to Default Order") {
                withAnimation(Motion.glide) { browser.prefs.chromeOrder = ChromePart.standard }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(Palette.muted)
            .onExitCommand { browser.arrangingChrome = false }
        }
        .padding(10)
        .frame(width: 336, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
    }
}

/// The tray of cells. Fixed widths, not measured: the tray lays its own
/// cells out, so the drag counts slots — a door carried by the hand
/// can't poison the measure of its own cell, which is what PinCarried
/// works around over on the pin grid.
private struct ChromeTray: View {
    @ObservedObject var browser: Browser

    private static let cell: CGFloat = 58
    private static let gap: CGFloat = 7
    private static var step: CGFloat { cell + gap }

    @State private var held: ChromePart?
    @State private var from = 0
    @State private var travel: CGFloat = 0

    private var parts: [ChromePart] { browser.prefs.chromeOrder }

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(parts) { part in
                cell(part, at: parts.firstIndex(of: part) ?? 0)
            }
        }
        .frame(height: 46)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: "chrome.tray")
        .animation(Motion.glide, value: parts)
    }

    private func cell(_ part: ChromePart, at: Int) -> some View {
        let shown = part.shown(browser.prefs, browser.fetches)
        return VStack(spacing: 3) {
            part.glyph
                .foregroundStyle(held == part ? Palette.ink : Palette.muted)
                .frame(height: 16)
            Text(part.title.said)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.ink.opacity(shown ? 0.8 : 0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 5)
        .frame(width: Self.cell)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.hover.opacity(held == part ? 0 : shown ? 0.7 : 0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
        .opacity(held == part || shown ? 1 : 0.65)
        .help((shown ? part.title : part.title + " — " + part.away(browser.prefs)).said)
        .animation(Motion.quick, value: shown)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // A click is the door's own show switch; a drag, the arranging.
        // Tap wants the press still, drag wants it moved — minimumDistance
        // is where they part, so both can sit on one cell.
        .onTapGesture {
            withAnimation(Motion.glide) { browser.toggleChrome(part) }
        }
        .offset(x: held == part ? shift(at: at) : 0)
        .zIndex(held == part ? 1 : 0)
        .shadow(color: .black.opacity(held == part ? 0.16 : 0), radius: 8, y: 3)
        .transaction { if held == part { $0.animation = nil } }
        .gesture(drag(part, at: at))
    }

    /// What the hand has carried it, less the ground its new cell already
    /// gave it — PinCarried's rule, from cells counted, not measured.
    private func shift(at: Int) -> CGFloat {
        travel - CGFloat(at - from) * Self.step
    }

    private func drag(_ part: ChromePart, at: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("chrome.tray"))
            .onChanged { value in drag(part, at: at, along: value.translation.width) }
            .onEnded { _ in
                withAnimation(Motion.settle) {
                    held = nil
                    travel = 0
                }
            }
    }

    /// The hand's every step: the cell under it takes the door.
    private func drag(_ part: ChromePart, at: Int, along: CGFloat) {
        if held != part {
            held = part
            from = at
        }
        travel = along
        let target = min(max(0, from + Int((travel / Self.step).rounded())), parts.count - 1)
        guard target != at else { return }
        withAnimation(Motion.settle) { browser.moveChrome(part, to: target, visible: parts) }
    }
}
