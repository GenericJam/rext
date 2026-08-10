# Desktop surface matrix

What rext covers — what's solid, what's partial, what's missing. Use this to
set expectations before starting an app, and as the source the component
backlog is generated from.

The reference surface is the union of **what SwiftUI, WinUI/WinForms, and
Compose Desktop expose**, cross-checked against what Electron/Tauri apps
actually reach for. It is deliberately *not* "everything mob has" — see
[Scope](#scope-what-transfers-from-mob-and-what-doesnt).

This doc is hand-maintained from inspection of `lib/rext/`, `native/compose`,
`native/macos`, and `native/windows`. If you add a capability, update the
matching row in the same commit.

Sibling doc: mob's [`mobile_surface_matrix.md`](../../mob/guides/mobile_surface_matrix.md),
which this clones. Where a row exists in both, mob's naming wins unless
desktop demands otherwise.

## Legend

| | |
|--|--|
| ✅ | Fully present — spec'd in `render_protocol.md`, implemented on all three backends |
| 🟡 | Partial — works on some backends, or narrow API / known caveats |
| ❌ | Missing — planned, not built |
| ⛔ | Out of scope — mobile-only idiom, or fundamentally incompatible with rext's architecture |

Per-backend columns: `✓` = supported, `—` = not supported, `n/a` = not applicable.

**Compose is the baseline and covers macOS + Windows + Linux from one Kotlin
codebase.** SwiftUI (macOS) and WinForms (Windows) are opt-in native *feel*
upgrades. A row can be ✅ only when all three are `✓`.

## The native-mapping rule

Compose draws with Skia, so it can render anything — including things a real
native control cannot express. That is the trap this matrix exists to catch.

> **Before a component is implemented in Compose, its row here must name the
> SwiftUI control and the WinForms control that will realize it, and flag any
> prop those can't honor natively.**

WinForms is the capability floor (its controls are Win32; arbitrary corner
radius, tinting, and custom track rendering are not free). A prop the floor
can't honor is not banned — it gets **platform-scoped**, the same way mob
scopes props with `ios:` / `android:`:

```elixir
props: %{
  padding: 12,
  macos: %{padding: 20}   # macOS sees 20; everything else sees 12
}
```

Platform-scoped props are **implemented** (`Rext.Platform`, resolved in
`Rext.Renderer`) on two axes — platform *and* backend (`compose:` / `swiftui:` /
`winforms:`), since a missing switch control is a backend limitation while menu
bar placement is an OS one. Precedence: unscoped < platform < backend.

---

## Scope: what transfers from mob, and what doesn't

Three buckets, and the third is the one that makes rext a desktop framework
rather than a mob port:

1. **Transfers directly** — layout, text, controls, lists. Same component,
   same props, different backends.
2. **Mobile-only, out of scope** — `camera_preview`, `tab_bar` (bottom nav is
   a phone idiom), safe-area insets, orientation lock, haptics,
   pull-to-refresh, bottom sheets. Marked ⛔ below.
3. **Desktop-only, absent from mob** — menu bar, context menus, keyboard
   focus/tab order and accelerators, hover and cursor, resizable panes,
   tables/trees, file dialogs, window chrome. mob has no reason to have these
   and rext can't be taken seriously without them.

---

## UI components (render tree)

Node types valid in a `render/1` tree. The set stays small and orthogonal —
composition over a fat component library (mob's rule, kept).

| Component | Status | Compose | SwiftUI | WinForms | Native mapping / notes |
|--|--|--|--|--|--|
| `column` | ✅ | ✓ | ✓ | ✓ | `Column` / `VStack` / `FlowLayoutPanel`. Has `spacing`, `padding`, `background`; missing `align`, `fill_width`, `fill_height` from mob |
| `row` | ✅ | ✓ | ✓ | ✓ | `Row` / `HStack` / `FlowLayoutPanel`. Same prop gaps as `column` |
| `text` | ✅ | ✓ | ✓ | ✓ | `Text` / `Text` / `Label`. Has `text`, `font_size`, `text_color`; missing `font_weight`, `text_align` |
| `button` | ✅ | ✓ | ✓ | ✓ | `Button` everywhere. Has `text`, `on_click`, `background` (SwiftUI only); missing `enabled`, `corner_radius`, `fill_width`, `weight` |
| `box` | ✅ | ✓ | ✓ | ✓ | Container: `padding`, `background`, `corner_radius`, `fill_width`. `Box`+`Modifier` / `ZStack`+modifiers / `Panel`. **`corner_radius` is accepted and ignored on WinForms** — Win32 panels have none, and it is not faked with an owner-drawn region; scope it with `winforms:` if an app needs the difference explicit. The parsers' phantom `"box"` default type is gone (now `"unknown"`) |
| `spacer` | ✅ | ✓ | ✓ | ✓ | `Spacer` both places / a zero-size docked `Panel`. `size` for fixed space; omit it to fill the remaining space along the parent's axis |
| `scroll` | ❌ | — | — | — | `ScrollView` / `Panel{AutoScroll=true}`. Desktop also needs horizontal + a visible scrollbar policy prop, which mob's version lacks |
| `divider` | ✅ | ✓ | ✓ | ✓ | `Divider` both places / a docked `Label` with a `BackColor`. `color`, `thickness` |
| `text_field` | ✅ | ✓ | ✓ | ✓ | `OutlinedTextField` / `TextField`+`SecureField` / `TextBox`. `value`, `placeholder`, `on_change`, `on_submit`, `secure`. mob's `keyboard_type` dropped (mobile-only). `on_focus`/`on_blur` deferred to the keyboard-focus work |
| `toggle` | ❌ | — | — | — | `Toggle` / `CheckBox`. **WinForms has no switch control** — a Win32 `CheckBox` is the honest native answer; a switch look would be owner-drawn. Decide: platform-scoped, or accept the checkbox |
| `checkbox` | ❌ | — | — | — | Desktop splits these where mobile doesn't: `Toggle{.checkbox}` / `CheckBox`. Distinct from `toggle` |
| `radio_group` | ❌ | — | — | — | `Picker{.radioGroup}` / `RadioButton` set. No mob equivalent |
| `slider` | ❌ | — | — | — | `Slider` / `TrackBar`. WinForms `TrackBar` is integer-stepped — a float `value` needs a scale factor, and `color` tinting is not supported natively |
| `progress` | ❌ | — | — | — | `ProgressView` / `ProgressBar`. Needs both determinate and indeterminate; mob's is indeterminate-only |
| `dropdown` | ❌ | — | — | — | `Picker` / `ComboBox`. No mob equivalent (mobile uses sheets) |
| `image` | ❌ | — | — | — | `AsyncImage` / `PictureBox`. Local + remote; mob has this and it's a plain gap |
| `list` | ❌ | — | — | — | `List` / `ListBox`. Selection semantics differ on desktop: single vs multi-select, keyboard navigation, and **double-click to activate** have no mobile analogue |
| `table` | ❌ | — | — | — | Desktop-only: sortable columns, resizable headers, row selection. `Table` / `DataGridView`. One of the biggest "this is a real desktop app" gaps |
| `tree` | ❌ | — | — | — | Desktop-only: `OutlineGroup`/`List` / `TreeView`. Expand/collapse, nested selection |
| `split_pane` | ❌ | — | — | — | Desktop-only: `HSplitView`/`VSplitView` / `SplitContainer`. User-draggable divider with persisted ratio |
| `tabs` | ❌ | — | — | — | Desktop tab strip (document tabs), *not* mob's bottom `TabBar`. `TabView` / `TabControl` |
| `context_menu` | ❌ | — | — | — | Desktop-only: right-click menu attached to any node. `.contextMenu` / `ContextMenuStrip` |
| `tooltip` | ❌ | — | — | — | Desktop-only, hover-triggered: `.help()` / `ToolTip`. No touch analogue |
| `webview` | ❌ | — | — | — | `WKWebView` / `WebView2`. Heavy: WebView2 needs a runtime dependency on Windows and Compose has no first-class web view. Defer |
| `lazy_list` | ❌ | — | — | — | Virtualized long list. Desktop scrolls large lists too, but `table` likely subsumes the real use case — revisit after `table` |
| `canvas` / `gpu_view` | ❌ | — | — | — | Shader/immediate-mode surface. mob has `GpuView` (Metal/GLES); desktop equivalent is a later question |
| `tab_bar` | ⛔ | n/a | n/a | n/a | Bottom navigation is a phone idiom. Desktop uses menus, toolbars, and `tabs` |
| `camera_preview` | ⛔ | n/a | n/a | n/a | Mobile capability; a desktop webcam view would be a plugin, not core |
| Unknown `type` | ✅ | ✓ | ✓ | ✓ | Renders children in a plain container (forward-compat, per protocol) |

## Window & chrome

rext's defining difference from mob: the unit is a window and apps run many.
Almost none of this exists in mob, and almost none of it is built here yet.

| Capability | Status | Compose | SwiftUI | WinForms | Notes |
|--|--|--|--|--|--|
| Open a window from Elixir | ✅ | ✓ | ✓ | ✓ | `Rext.open/2`, `Rext.boot/1`; window = supervised GenServer |
| Window title | ✅ | ✓ | ✓ | ✓ | `:title` option |
| Initial size | ✅ | ✓ | ✓ | ✓ | `:size` option |
| Window icon | 🟡 | ✓ | — | — | Compose only, via `REXT_ICON` |
| **One renderer draws one window** | ✅ | ✓ | ✓ | ✓ | The bridge fans out to many renderers, each bound to the window it names in `hello`; `mix rext.run` launches one per declared window and halts only when the last detaches. See `decisions/2026-08-09-multi-window-rendering.md`. **Visually verified on macOS 2026-08-09**: two windows on screen at once, the second tracking the first live |
| Close / minimize / maximize from Elixir | ❌ | — | — | — | Programmatic control of window state |
| Resizable / min / max size | ❌ | — | — | — | Constraint props at open time |
| Window position + restore | ❌ | — | — | — | Save/restore geometry across launches |
| Focus / raise / always-on-top | ❌ | — | — | — | |
| Window lifecycle events → BEAM | ❌ | — | — | — | resize, move, focus, blur, close-requested (needed to veto a close) |
| Menu bar (app / window menu) | ❌ | — | — | — | `Commands` / `MenuStrip`. macOS puts it in the system bar, Windows in-window — same declaration, different placement |
| System tray / notification area | ❌ | — | — | — | `MenuBarExtra` / `NotifyIcon` |
| Native notifications | ❌ | — | — | — | `UNUserNotificationCenter` / toast API |
| Multi-monitor / DPI scaling | ❌ | — | — | — | Per-monitor DPI on Windows is a known source of blurry-window bugs |
| Dark mode / system appearance | ❌ | — | — | — | mob has `Mob.Theme.color_scheme/0` + adaptive watching; rext's theme is a fixed dark palette |

## Input

Desktop input is mouse + keyboard first. mob marks most of this ❌ because
phones don't need it; rext can't.

| Capability | Status | Compose | SwiftUI | WinForms | Notes |
|--|--|--|--|--|--|
| Click | ✅ | ✓ | ✓ | ✓ | `on_click` → `click` event with `tag` |
| Right-click / secondary click | ❌ | — | — | — | Prerequisite for `context_menu` |
| Double-click | ❌ | — | — | — | Row activation in `list`/`table` |
| Hover enter/leave | ❌ | — | — | — | Prerequisite for `tooltip`; no touch analogue |
| Cursor shape | ❌ | — | — | — | pointer / text / resize |
| Scroll wheel | ❌ | — | — | — | Distinct from touch scroll: needs delta events |
| Keyboard focus + tab order | ❌ | — | — | — | **Table stakes for desktop.** Tab/Shift-Tab traversal, focus ring, programmatic focus |
| Keyboard shortcuts / accelerators | ❌ | — | — | — | Cmd/Ctrl chords, menu-item bindings |
| Raw key events | ❌ | — | — | — | keydown/keyup with modifiers |
| Text selection + clipboard in fields | ❌ | — | — | — | Select-all, cut/copy/paste — expected to work without app code |
| Drag and drop (files onto window) | ❌ | — | — | — | Very common desktop entry point |
| Drag and drop (in-app reorder) | ❌ | — | — | — | |
| Touch / gestures | ⛔ | n/a | n/a | n/a | Touchscreen laptops exist; not a target |

## System integration

| Capability | Status | Notes |
|--|--|--|
| Clipboard (get/put) | ❌ | mob has `Mob.Clipboard`; direct port |
| Open URL in browser | ❌ | mob has `Mob.Device.open_url/1`; direct port |
| File open dialog | ❌ | `NSOpenPanel` / `OpenFileDialog`. Desktop equivalent of mob's document picker |
| File save dialog | ❌ | `NSSavePanel` / `SaveFileDialog`. No mobile analogue |
| Folder picker | ❌ | Desktop-only |
| Alert / message dialog | ❌ | mob has `Mob.Alert`; `NSAlert` / `MessageBox` |
| Recent files / jump list | ❌ | Platform-specific, low priority |
| Launch at login | ❌ | Plugin candidate |
| Single-instance enforcement | ❌ | Related to the release launcher's fixed-port limitation |

## Protocol & styling

The seam everything above depends on.

| Capability | Status | Notes |
|--|--|--|
| JSON node format (`type`/`props`/`children`) | ✅ | `render_protocol.md` |
| Two transports (socket + in-process NIF) | ✅ | `Rext.Bridge`, `Rext.NifBridge` |
| Unknown-type forward compat | ✅ | Renders children in a plain container |
| Color tokens | 🟡 | 8 colors, fixed dark palette. No light theme, no user-supplied palette |
| Spacing tokens | 🟡 | 5 steps (`space_xs`…`space_xl`) |
| Radius tokens | ❌ | mob has `:radius_sm/md`; `box` and `button` need them |
| Text-size / weight tokens | ❌ | mob has `:base` etc.; `text` takes raw px only |
| **Platform-scoped props** (`macos:`/`windows:`/`linux:`) | ✅ | Two axes: platform *and* backend (`compose:`/`swiftui:`/`winforms:`), since Compose is the baseline everywhere and natives are an opt-in upgrade. Precedence unscoped < platform < backend; resolved in `Rext.Renderer` and stripped before the wire, so backends see one flat prop set. `Rext.Platform` |
| Prop validation / unknown-prop diagnostics | ✅ | `Rext.Catalog` + a warn-once-per-window check in `Rext.Window`. Reports, never drops — a newer backend may know a prop this BEAM doesn't |
| Component catalog kept in sync with backends | ❌ | Already drifted: `box` ships on all three, documented on none |
| Template sigil (`~UI`) | ❌ | mob has `~MOB` with `:if`/`:for`. rext writes raw maps — verbose, and the gap most visible to a new user |
| Composite / reusable components | ❌ | mob has function + tag composites |
| `Rext.Style` reusable styles | ❌ | mob has `Mob.Style` |

## Agent verification

`PLAN.md`'s "verification frontier" — the investment that removes the human
from the pixel-checking loop. Tracked here because it's a capability like any
other.

| Capability | Status | Notes |
|--|--|--|
| Introspect window state over dist | ✅ | `Rext.Test.window/assigns/tree/find` |
| Drive controls over dist | ✅ | `Rext.Test.click/2`, `input/3` |
| Works headlessly (no renderer) | ✅ | State is authoritative on the BEAM |
| Screenshot over dist | ❌ | Agent cannot see a window today |
| Accessibility-tree walk | 🟡 | `Rext.Test.native_tree/2` — a `describe`/`described` round-trip; the backend reports what it built, so a silently dropped node is visible. WinForms walks the **real** `Control` tree; SwiftUI/Compose report the branch taken (neither exposes an inspectable widget tree in-process) |
| Synthetic OS-level event injection | ❌ | mob's "cocoon" ambition |

## Accessibility

| Capability | Status | Notes |
|--|--|--|
| Accessibility labels on nodes | ✅ | `accessibility_label`, valid on every node type → `accessibilityLabel` / `contentDescription` / `AccessibleName`. Also the substrate for the AX-tree walk above |
| Screen reader support | ❌ | VoiceOver / Narrator |
| Keyboard-only operation | ❌ | Depends on focus + tab order |
| High contrast / reduce motion | ❌ | |

---

## Open decisions

These change the shape of the backlog and aren't mine to settle:

1. ~~**Prop vocabulary**~~ — **settled.** Compose + SwiftUI are the naming
   authority; WinForms is the capability floor but gets no vote on names. See
   `decisions/2026-08-08-component-nomenclature.md` for the vocabulary table
   and the tiebreak order. A breaking rename is owed
   (`label`→`text`, `size`→`font_size`, `color`→`text_color`/`background`,
   `gap`→`spacing`) — do it before the catalog grows.
2. **Event model.** mob delivers `{:tap, tag}` to `handle_info/2` via
   `{pid, tag}` props; rext routes `handle_event("click", %{"tag" => ...})`,
   LiveView-shaped. rext's reads better for desktop and matches the LiveView
   mental model — recommend keeping it, but it should be a decided divergence
   rather than an accident.
3. **`toggle` on WinForms.** Win32 has no switch. Ship a `CheckBox` and accept
   the look, or owner-draw a switch? This is the first real test of the
   capability-floor rule.
4. **Does `table` subsume `list` and `lazy_list`?** Building `table` well may
   make the other two redundant on desktop.

## How to use this matrix

- **Starting an app**: scan ❌ rows to see what you'd have to work around.
- **Filing work**: every ❌ / 🟡 row is a backlog candidate. Issues are in
  `bd` (`bd list`); this doc is the source they're generated from.
- **Adding a capability**: update the row in the same commit, and fill the
  native-mapping note *before* implementing.
- **Ordering**: `PLAN.md` holds the roadmap and the thesis. This is a
  snapshot of reality, not a commitment — some ❌ rows will stay ❌.

## Related docs

- [`render_protocol.md`](render_protocol.md) — the contract all backends bind to
- [`../PLAN.md`](../PLAN.md) — thesis, backend strategy, roadmap
- [`../CLAUDE.md`](../CLAUDE.md) — conventions, toolchain, quality gates
- mob's [`components.md`](../../mob/guides/components.md) — the component
  reference this matrix is diffed against
