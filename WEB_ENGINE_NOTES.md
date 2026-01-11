# Web Engine Improvement Notes

## Immediate quality issues (Unity rendering)
- Text is blurry: ensure 1:1 pixel mapping between the web view size and the UI target size (no CanvasScaler scaling). Use point filtering for the UI texture.
- Image appears flipped: add a render origin/row-order flag in the native API (top-left vs bottom-left) to avoid Unity-side UV flips.
- Color correctness: verify RGBA/BGRA channel order and alpha premultiplication; expose pixel format in the Unity wrapper.

## Web engine updates needed for UI/UX
- Add a hit-test API for click-through UIs: `webr_view_hit_test(x, y)` returning whether the pixel is interactive + cursor type.
- Expose transparent background and alpha-preserving render output (no forced opaque clear).
- Provide a device-pixel-ratio or scale API so text renders crisp at high DPI.

## Hot reload (HTML/CSS)
- Add `webr_view_set_html()` support for fast reloads (already present) and an explicit `webr_view_set_css()` to update styles without full document reload.
- Optional file-watcher helper in host code (Unity side) to detect HTML/CSS changes.
- Consider `webr_view_set_base_path()` so relative assets load from a local folder during dev.

## Fullscreen + resize behavior
- Support `webr_view_resize()` in the engine with predictable re-layout, and return a `needs_render` flag after resize.
- Ensure resize is safe to call every frame while the Unity screen size changes.

## Tick/update loop
- UI needs a regular `tick()` for animations, input, JS timers, and rendering.
- For static pages, tick once after load and on input/resize; for interactive UI, tick each frame or at a fixed cadence.

## Rendering pipeline
- Add explicit `device_pixel_ratio` or `scale` parameter so UI can render at higher DPI without blur.
- Provide a resize API that supports integer pixel sizing and a `needs_render` flag after resize.
- Ensure `RenderToTexture` handles stride and row-order correctly for Unity textures.
- Consider exposing a direct GPU texture path later (shared texture) to avoid CPU copy.

## Input and interop
- Provide full input mapping: mouse, keyboard, scroll, text input, IME, clipboard.
- Normalize input coordinates and add helpers for Unity UI coordinate conversion.
- Expose explicit focus APIs and tab navigation support.

## Events and logging
- Define a stable event queue contract (thread safety, lifetime, ownership) and allow polling by type.
- Include JS console severity level and optional stack traces.

## Stability and diagnostics
- Provide clear error codes for layout/render vs script errors.
- Add a diagnostic callback hook for internal logs.
- Add unit tests for bitmap layout, stride, and color order.

## Packaging and build
- Document supported platforms and exact library names.
- Provide per-platform feature flags or optional modules.
