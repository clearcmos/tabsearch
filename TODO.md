# TODO

## Liquid Glass / Tahoe Spotlight look-and-feel (deferred, not started)

Goal: make the search panel's appearance and present/dismiss animation closely match
macOS 26 (Tahoe) Spotlight, using the public Liquid Glass APIs.

### Reality check
- Near-indistinguishable is achievable; literally identical is not. Spotlight is a private
  system component we cannot embed, and Apple does not publish its exact metrics or animation
  curves - we replicate with the same public primitives.
- The material is the real thing: Liquid Glass is public API in the macOS 26 SDK. This
  machine (macOS 26.5, SDK 26.5, Swift 6.3, target macosx26.0) builds it with Command Line
  Tools; no full Xcode required.

### Steps
1. Deployment target (`Package.swift`, currently `platforms: [.macOS(.v13)]`)
   - Recommended: keep 13 and gate the glass code with `if #available(macOS 26, *)`, falling
     back to today's `.regularMaterial`. Only the panel background branches.
   - Alternative: bump TabSearchBar to `.macOS(.v26)` (simplest; drops pre-26 builds).

2. Swap the material (`Sources/TabSearchBar/SearchView.swift`, currently lines 67-69)
   - Replace `.background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))`
     with `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: <R>))` (macOS 26+).
   - The host window is already borderless + clear (see `SearchPanelController.makePanel()`),
     which glass needs - no window change required.
   - If later split into multiple glass surfaces (field vs results), wrap them in a
     `GlassEffectContainer` so they blend/morph correctly. A single surface needs only the
     bare modifier.

3. Match Spotlight geometry/typography (`SearchView.swift`)
   - Corner radius: Tahoe Spotlight is larger than our current 12; measure against the live
     panel (try ~18-22).
   - Search field: larger height, leading magnifier glyph sizing/spacing, placeholder style
     (currently field `font(.system(size: 20))`, magnifier size 18).
   - Panel size is fixed 680x420 in both `SearchView` and `makePanel()`/`host`. Optional
     later: size-to-content (field-only when empty, expand as rows appear), like Spotlight.

4. Present/dismiss animation (`Sources/TabSearchBar/SearchPanelController.swift`,
   `show()`/`hide()`)
   - Spotlight uses a scale + fade spring. Drive a SwiftUI spring (scaleEffect + opacity)
     from an `isPresented` flag in `SearchModel`. Exact spring values are private - tune by
     eye against live Spotlight. `animationBehavior` is `.utilityWindow`; consider `.none`
     and drive motion in SwiftUI for full control.

5. Appearance & legibility: verify Light/Dark, and that monospaced result rows stay legible
   over glass (may need a subtle scrim behind text).

### Verification
- `make app` (or `make bundle && make install-app`), relaunch, press Shift+Cmd+F.
- Put real Tahoe Spotlight (Cmd+Space) beside our panel and compare: translucency, corner
  radius, field sizing, present/dismiss motion. Check Light and Dark, and over a full-screen
  Terminal.

### Honest limitation
Result is "a casual observer cannot tell them apart," not pixel/frame-identical: same public
material, geometry matched by eye, animation a close spring approximation.

### References
- glassEffect(_:in:): https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- GlassEffectContainer: https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- Applying Liquid Glass to custom views: https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- AppKit equivalents: NSGlassEffectView, NSGlassEffectContainerView
