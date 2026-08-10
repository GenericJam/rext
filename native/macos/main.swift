// rext — macOS SwiftUI render backend (prototype).
//
// Owns NSApplication / the main thread, connects back to the BEAM over a
// localhost TCP socket (4-byte length-framed JSON, matching Elixir's
// `{:packet, 4}`), decodes render frames into a SwiftUI view tree, and echoes
// interaction events back. This is the "render backend" end of rext's
// transport-agnostic protocol: the same decode/draw logic is what a future
// in-process NIF host would call directly instead of reading from a socket.
//
// Build:  swiftc main.swift -o rext_renderer -framework AppKit -framework SwiftUI -framework Network
// Run:    REXT_PORT=8137 ./rext_renderer

import AppKit
import SwiftUI
import Network
import Foundation

func eprint(_ s: String) {
    FileHandle.standardError.write(("[rext_renderer] " + s + "\n").data(using: .utf8)!)
}

// ── Render-tree model ────────────────────────────────────────────────────────

final class RNode: Identifiable {
    // Identity is the node's *path* in the tree ("0.2.1"), not a fresh UUID.
    // A frame arrives on every state change and is re-parsed from scratch, so
    // per-parse identity makes ForEach treat every node as new: SwiftUI tears
    // the hierarchy down and rebuilds it each frame. That drops keyboard focus
    // after a single keystroke, and — because a rebuilt TextField re-runs
    // onAppear, which fires onChange, which sends another event — spins the
    // bridge in a render/event loop.
    let id: String
    let type: String
    let props: [String: Any]
    let children: [RNode]

    init(id: String, type: String, props: [String: Any], children: [RNode]) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
    }

    static func parse(_ dict: [String: Any], path: String = "0") -> RNode {
        let type = dict["type"] as? String ?? "unknown"
        let props = dict["props"] as? [String: Any] ?? [:]
        let kids = (dict["children"] as? [[String: Any]] ?? [])
            .enumerated()
            .map { RNode.parse($1, path: "\(path).\($0)") }
        return RNode(id: path, type: type, props: props, children: kids)
    }

    func str(_ key: String) -> String? { props[key] as? String }
    func bool(_ key: String) -> Bool? { props[key] as? Bool }
    func num(_ key: String) -> CGFloat? {
        if let n = props[key] as? NSNumber { return CGFloat(truncating: n) }
        return nil
    }
}

// ── Shared UI state ──────────────────────────────────────────────────────────

final class RenderState: ObservableObject {
    @Published var root: RNode?
    // event, tag, value — value is "" for valueless events like a click.
    var send: ((String, String, String) -> Void)?

    // Which window this renderer draws. One renderer surface per window is the
    // desktop model; frames for other windows (a multi-window app pushes several
    // over the same bridge) are ignored here.
    let target: String

    init(target: String) {
        self.target = target
    }

    func apply(frame: [String: Any]) {
        guard frame["t"] as? String == "render",
              frame["window"] as? String == target,
              let tree = frame["tree"] as? [String: Any] else { return }
        let node = RNode.parse(tree)
        eprint("decoded frame: window=\(target) root=\(node.type) "
            + "children=\(node.children.count) firstText=\(String(describing: firstText(node)))")
        DispatchQueue.main.async { self.root = node }
    }

    // What this renderer built, as it built it. SwiftUI exposes no inspectable
    // view tree from inside the process, so `kind` is the concrete SwiftUI view
    // the switch in NodeView produces for that node type — and crucially, a
    // type we don't handle reports as "VStack(fallback)" rather than looking
    // like it drew fine. That is the case a green build hides.
    func describe(_ n: RNode?) -> Any {
        guard let n = n else { return NSNull() }

        let kind: String
        switch n.type {
        case "column": kind = "VStack"
        case "row": kind = "HStack"
        case "text": kind = "Text"
        case "button": kind = "Button"
        case "box": kind = "ZStack"
        case "spacer": kind = "Spacer"
        case "divider": kind = "Divider"
        case "text_field": kind = "TextField"
        default: kind = "VStack(fallback)"
        }

        return [
            "kind": kind,
            "label": (n.str("accessibility_label") ?? NSNull()) as Any,
            "children": n.children.map { describe($0) },
        ]
    }

    private func firstText(_ n: RNode) -> String? {
        if n.type == "text" { return n.str("text") }
        for c in n.children { if let t = firstText(c) { return t } }
        return nil
    }
}

// ── Color helper ─────────────────────────────────────────────────────────────

func rextColor(_ hex: String?) -> Color? {
    guard let hex = hex, hex.hasPrefix("#"), hex.count == 7 else { return nil }
    let v = Int(hex.dropFirst(), radix: 16) ?? 0
    return Color(
        red: Double((v >> 16) & 0xFF) / 255.0,
        green: Double((v >> 8) & 0xFF) / 255.0,
        blue: Double(v & 0xFF) / 255.0
    )
}

// ── SwiftUI views ────────────────────────────────────────────────────────────

// Applies the node's accessibility label to whatever view it wraps, so the
// hook lives in one place instead of on every branch below.
struct A11yLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label = label, !label.isEmpty {
            content.accessibilityLabel(Text(label))
        } else {
            content
        }
    }
}

// Text input keeps local state: the field is the live thing the user is typing
// into, and the BEAM's value is an echo that arrives a round-trip later. Binding
// straight to the incoming value would move the caret on every keystroke.
struct TextFieldNode: View {
    let node: RNode
    @EnvironmentObject var state: RenderState
    @State private var text = ""
    @State private var lastSent: String?
    // True while applying a server value, so the resulting text change isn't
    // mistaken for the user typing and echoed straight back.
    @State private var applyingRemote = false

    var body: some View {
        let incoming = node.str("value") ?? ""
        let placeholder = node.str("placeholder") ?? ""

        field(placeholder)
            .textFieldStyle(.roundedBorder)
            .onAppear {
                applyingRemote = true
                text = incoming
            }
            .onChange(of: incoming) { _, new in
                // Adopt a server value only when it is not the echo of our own
                // last edit — otherwise every keystroke fights the round-trip.
                if new != lastSent {
                    applyingRemote = true
                    text = new
                    lastSent = new
                }
            }
            .onChange(of: text) { _, new in
                if applyingRemote {
                    applyingRemote = false
                    return
                }

                lastSent = new
                if let tag = node.str("on_change") { state.send?("change", tag, new) }
            }
            .onSubmit {
                if let tag = node.str("on_submit") { state.send?("submit", tag, text) }
            }
    }

    @ViewBuilder private func field(_ placeholder: String) -> some View {
        if node.bool("secure") == true {
            SecureField(placeholder, text: $text)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

struct NodeView: View {
    let node: RNode
    @EnvironmentObject var state: RenderState

    var body: some View {
        content.modifier(A11yLabel(label: node.str("accessibility_label")))
    }

    @ViewBuilder private var content: some View {
        switch node.type {
        case "column":
            VStack(alignment: .leading, spacing: node.num("spacing") ?? 8) {
                ForEach(node.children) { NodeView(node: $0) }
            }
            .padding(node.num("padding") ?? 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(rextColor(node.str("background")))

        case "row":
            HStack(spacing: node.num("spacing") ?? 8) {
                ForEach(node.children) { NodeView(node: $0) }
            }
            .padding(node.num("padding") ?? 0)

        case "text":
            Text(node.str("text") ?? "")
                .font(.system(size: node.num("font_size") ?? 15))
                .foregroundColor(rextColor(node.str("text_color")) ?? .primary)

        case "button":
            Button(action: {
                if let tag = node.str("on_click") { state.send?("click", tag, "") }
            }) {
                Text(node.str("text") ?? "")
                    .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(rextColor(node.str("background")) ?? Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(8)

        case "box":
            // ZStack + modifiers is SwiftUI's container idiom; corner radius
            // clips the background, so order matters here.
            ZStack { ForEach(node.children) { NodeView(node: $0) } }
                .padding(node.num("padding") ?? 0)
                .background(rextColor(node.str("background")))
                .cornerRadius(node.num("corner_radius") ?? 0)
                .frame(maxWidth: node.bool("fill_width") == true ? .infinity : nil)

        case "spacer":
            // No size => fill remaining space, which is Spacer's default.
            if let size = node.num("size") {
                Spacer().frame(width: size, height: size)
            } else {
                Spacer()
            }

        case "text_field":
            TextFieldNode(node: node)

        case "divider":
            Divider()
                .frame(height: node.num("thickness") ?? 1)
                .background(rextColor(node.str("color")) ?? Color.gray)

        default:
            VStack { ForEach(node.children) { NodeView(node: $0) } }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: RenderState
    var body: some View {
        Group {
            if let root = state.root {
                NodeView(node: root)
            } else {
                Text("Waiting for BEAM…").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// ── Connection (4-byte length-framed JSON) ───────────────────────────────────

final class Bridge {
    private let conn: NWConnection
    private let state: RenderState
    // Once we've connected, a drop means the BEAM went away — so we quit too,
    // keeping the app's lifetime tied to the BEAM (no orphaned renderer).
    private var wasReady = false

    init(port: UInt16, state: RenderState) {
        self.state = state
        conn = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    func start() {
        conn.stateUpdateHandler = { [weak self] st in
            guard let self = self else { return }
            eprint("connection state: \(st)")
            switch st {
            case .ready:
                self.wasReady = true
                eprint("connected; hello window=\(self.state.target)")
                self.sendRaw(["t": "hello", "renderer": "macos-swiftui", "window": self.state.target])
                self.readFrame()
            case .failed, .cancelled:
                if self.wasReady { self.quit("bridge disconnected") }
            default:
                break
            }
        }
        state.send = { [weak self] event, tag, value in
            guard let self = self else { return }
            eprint("send event=\(event) tag=\(tag) value=\(value.debugDescription)")
            self.sendRaw([
                "t": "event", "window": self.state.target,
                "event": event, "tag": tag, "value": value,
            ])
        }
        conn.start(queue: .global())
    }

    // Terminate the renderer when the BEAM connection ends.
    private func quit(_ reason: String) {
        eprint("\(reason) — quitting renderer")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    private func readFrame() {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, err in
            guard let self = self else { return }
            if err != nil || data == nil || isComplete {
                if self.wasReady { self.quit("bridge closed") }
                return
            }
            guard let hdr = data, hdr.count == 4 else { return }
            let len = hdr.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            self.conn.receive(minimumIncompleteLength: Int(len), maximumLength: Int(len)) { body, _, _, err in
                if let body = body, err == nil,
                   let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    if obj["t"] as? String == "describe",
                       obj["window"] as? String == self.state.target {
                        self.sendRaw([
                            "t": "described",
                            "window": self.state.target,
                            "ref": obj["ref"] as? String ?? "",
                            "tree": self.state.describe(self.state.root),
                        ])
                    } else {
                        self.state.apply(frame: obj)
                    }
                }
                self.readFrame()
            }
        }
    }

    private func sendRaw(_ obj: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: obj) else { return }
        var len = UInt32(payload.count).bigEndian
        var frame = Data(bytes: &len, count: 4)
        frame.append(payload)
        conn.send(content: frame, completion: .contentProcessed { _ in })
    }
}

// ── App bootstrap ────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state: RenderState
    var window: NSWindow?

    init(state: RenderState) {
        self.state = state
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        eprint("applicationDidFinishLaunching window=\(state.target)")

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        win.title = state.target.capitalized
        win.center()
        win.contentView = NSHostingView(rootView: ContentView().environmentObject(state))
        win.makeKeyAndOrderFront(nil)
        window = win

        NSApp.activate(ignoringOtherApps: true)
    }

    // Closing the window quits the renderer (standard single-window desktop
    // app). Its socket then drops, which halts the BEAM (see RextDev.Boot) —
    // so closing the window shuts the whole app down.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool {
        true
    }
}

// A GUI app cannot open a macOS WindowServer (SkyLight) session as root — the
// session is per-login-user. As root, NSApplication init segfaults deep inside
// SkyLight rather than failing cleanly. Refuse up front with a clear message so
// the cause is obvious. (This happens when the BEAM was started via sudo/root
// and spawned the renderer as a child, inheriting uid 0.)
if geteuid() == 0 {
    eprint("refusing to run as root: the macOS WindowServer is per-user. "
        + "Run rext (and `mix rext.run`) as your normal login user, not sudo/root.")
    exit(1)
}

// Start networking independent of AppKit: the connection lives on a background
// queue and must come up even if the window server / GUI session is unavailable
// (e.g. launched detached from a login session). The delegate only owns the
// window and shares the same RenderState.
let port = UInt16(ProcessInfo.processInfo.environment["REXT_PORT"] ?? "8137") ?? 8137
let target = ProcessInfo.processInfo.environment["REXT_WINDOW"] ?? "main"
eprint("starting; port=\(port) window=\(target)")
let state = RenderState(target: target)
let delegate = AppDelegate(state: state)
let bridge = Bridge(port: port, state: state)
bridge.start()

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
