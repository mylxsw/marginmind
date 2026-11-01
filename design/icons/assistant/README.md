# AI assistant icon

Approved circular mark: two capsule eyes, each tilted clockwise by 8°.

- `iris.svg`: blue purple, default (#6254DB → #3278C8, white eyes).
- `jade.svg`: teal (#087E84 → #168B7B, white eyes).
- `apricot.svg`: apricot (#F9AE62 → #F28B52, #643321 eyes).

The 256×256 masters include export padding. `MMAssistantIcon` draws the same geometry natively in Flutter, cropped to the circle so the mark fills the requested icon size. All three palettes are available under Settings → General → AI assistant icon. The choice persists as `settings.assistantIcon`.

Motion moves only the eyes; the circle and colours remain fixed:

- Rest: still, with no scheduled animation frames or idle timer.
- Hover: one 240 ms blink, then a small gaze towards the pointer; exit returns to centre with a critically damped spring.
- Touch/click: one blink, without delaying or consuming the containing button's action.
- Work: a subtle 2.4 s scanning cycle, blended in/out over 220 ms. The assistant panel and floating answer follow their actual conversation's running state; finishing or stopping gives one blink.
- Accessibility: system/app reduced motion, hidden ticker subtrees and backgrounding suspend motion. Settings colour swatches stay static.

Native rendering preview can be exported with `MM_ASSISTANT_MOTION_PREVIEW=<directory> MM_FONT=<font file> flutter test --no-pub test/assistant_icon_motion_test.dart` from `packages/mm_design`.
