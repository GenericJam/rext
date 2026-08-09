# Component nomenclature follows Compose + SwiftUI, not WinForms

- Date: 2026-08-08
- Status: accepted
- Resolves "Open decision 1" in `guides/desktop_surface_matrix.md`.

## Context

rext's prop vocabulary was inherited piecemeal and has already drifted into
inconsistency at five components: `text` nodes take a `text` prop while
`button` nodes take a `label` prop for the same concept, and `color` means
*foreground* on `text` but *background* on `button`. The catalog is about to
triple, so the naming rule needs to be settled before the drift compounds.

Desktop toolkits do not agree. For the button-caption case alone: WinForms and
Qt say `Text`, GTK says `label`, WinUI says `Content`, and SwiftUI and Compose
take a content closure with no string prop at all. "Abdicate to the underlying
paradigm" gives no answer when the paradigms disagree.

## Decision

**When toolkits disagree, follow Compose and SwiftUI.**

Two reasons, in order of weight:

1. **Migration path.** Far more developers will arrive at rext from mob than
   from WinForms. mob's backends are SwiftUI and Compose, so their vocabulary
   is the one rext's actual audience already has in their fingers.
2. **Cross-platform ambition.** Compose Multiplatform and SwiftUI are both
   aimed beyond their home OS. Their naming is designed to survive being
   lifted off one platform; WinForms' is not.

WinForms remains the *capability* floor (see the native-mapping rule in
`guides/desktop_surface_matrix.md`) but gets no vote on *naming*. A capability
floor and a naming authority are different jobs, and WinForms is the least
representative of the five desktop toolkits — it should not get a third of the
vote just because it happens to be one of the three backends built.

### The resulting vocabulary

| Concept | Compose | SwiftUI | mob | rext today | **Decision** |
|--|--|--|--|--|--|
| Display string | `text` | `Text(_)` | `text` | `text` / `label` | **`text`** |
| Caption on a control | — | — | `label` | — | **`label`** |
| Font size | `fontSize` | `.font(size:)` | `text_size` | `size` | **`font_size`** |
| Font weight | `fontWeight` | `.fontWeight()` | `font_weight` | — | **`font_weight`** |
| Text alignment | `textAlign` | `.multilineTextAlignment()` | `text_align` | — | **`text_align`** |
| Foreground color | `color` | `.foregroundStyle()` | `text_color` | `color` | **`text_color`** ¹ |
| Background | `Modifier.background` | `.background()` | `background` | `background` | **`background`** |
| Space between children | `Arrangement.spacedBy` | `spacing:` | `gap` | `gap` | **`spacing`** |
| Padding | `Modifier.padding` | `.padding()` | `padding` | `padding` | **`padding`** |
| Corner radius | `RoundedCornerShape` | `.cornerRadius()` | `corner_radius` | — | **`corner_radius`** |
| Primary action | `onClick` | `Button(action:)` | `on_tap` | `on_click` | **`on_click`** |
| Interactive state | `enabled` | `.disabled()` | `disabled` | — | **`enabled`** ² |
| Fill available width | `fillMaxWidth` | `.frame(maxWidth:)` | `fill_width` | — | **`fill_width`** ³ |
| Flex weight | `Modifier.weight` | `.layoutPriority` | `weight` | — | **`weight`** |

`camelCase` transliterates to `snake_case`.

**`text` vs `label`.** `text` is the primary content a node displays (`text`,
`button`). `label` is an identifying caption for a control that carries its own
*value* (`toggle`, `slider`, `text_field`). This is mob's distinction and it's
a good one — keep it.

¹ **Deviation, deliberate.** Compose's `Text` takes a bare `color` because it's
a typed per-component signature where the meaning is unambiguous. rext's
protocol is *flat props across heterogeneous node types*, where a bare `color`
is not unambiguous — and in rext today it literally means foreground on `text`
and background on `button`. `text_color` + `background` disambiguates. This is
rule 3 below applied: name the role in our model, not the platform's
implementation.

² SwiftUI says `.disabled()`, Compose says `enabled =`. Split, so take the
positive form — `enabled: true` by default reads better than a double negative
at the call site.

³ Neither exposes this as a prop (both are modifiers). mob's name is good and
costs nothing.

### The tiebreak order, for future cases

1. Toolkits agree → take their word.
2. They disagree → follow **Compose + SwiftUI** (this decision).
3. Compose and SwiftUI disagree with each other → name the **role in rext's
   model**, not any platform's implementation. The name must survive a backend
   swap, and ours will swap — `PLAN.md` has WinUI 3 as a later upgrade over
   WinForms.
4. Still tied → match **mob**, to keep a future shared `beam_native_ui`
   package cheap.
5. Never let a backend's *limitation* name a concept. Calling `toggle` a
   `checkbox` because Win32 lacks a switch would export a Win32 gap to every
   platform, permanently.

## Consequences

**This diverges from mob in three places.** Accepted — the rule is the
authority, and mob compatibility is only tiebreak 4:

- `gap` → `spacing`
- `text_size` → `font_size`
- `disabled` → `enabled`

Worth noting the rule *removes* an inconsistency rather than adding one: mob
pairs `text_size` with `font_weight`, mixing two prefixes for one concept.
Compose is consistent (`fontSize`/`fontWeight`), and so is this.

`on_tap` → `on_click` is not really a divergence — desktop input is a click,
Compose Desktop says `onClick`, and rext already had it right.

**A breaking rename is now owed**, touching `lib/rext/renderer.ex`, all three
backends (`native/compose`, `native/macos`, `native/windows`),
`guides/render_protocol.md`, `dev/demo.exs`, `rext_demo`, and `rext_new`'s
template:

| From | To |
|--|--|
| `label` (on `button`) | `text` |
| `size` (on `text`) | `font_size` |
| `color` (on `text`) | `text_color` |
| `color` (on `button`) | `background` |
| `gap` | `spacing` |

Doing this at five components is cheap. Doing it at twenty-five is not — which
is the whole reason to settle it now.

## Alternatives considered

**Match mob exactly.** Cheapest path to a shared `beam_native_ui` package, and
mob-to-rext is the real migration path. Rejected because it would import mob's
own `text_size`/`font_weight` inconsistency, and because mob's names are
themselves derived from SwiftUI + Compose — following the source directly gets
the same benefit without inheriting the drift.

**Follow the majority of built backends.** Would have given WinForms/Qt-style
naming a third of the vote. Rejected: the backend set is an accident of build
order, not a statement about the ecosystem, and WinForms is the one scheduled
for replacement.
