# GUL-541 touch interaction evidence

Captured on 2026-10-28 using the iPad Pro 13-inch (M5), iOS 26.5 simulator, with a debug build of the application and the bundled sample study set. The iOS runner was generated in a separate working copy; runner files are outside this change.

- [Library long press](ipad-library-long-press.png): holding a study set opens its menu, including rename and delete. Touch menu rows are 44 logical points high.
- [Touch pan](ipad-touch-pan.png): a single finger dragged blank map space; the map moved without drawing a selection rectangle. Multiple Selection sits below the existing map toolbar.
- [Node long press](ipad-node-long-press.png): holding “Spaced repetition” opens the node menu.
- [Long press followed by drag](ipad-long-press-drag.png): the same held touch moved “Spaced repetition” onto “How we forget”; it became that node’s child and the menu closed.

Automated widget tests additionally cover two-finger pinch, holding two fingers on nodes, cancellation, touch multiple selection, Pencil drawing versus finger scrolling/selection, menu keyboard focus, hybrid input, and keyboard insets. Mouse tests keep their existing assertions and now identify mouse events explicitly.

Physical Apple Pencil input, haptic sensation and external iPad trackpad hardware were not available for manual testing. The simulator screenshots retain the existing platform layout; safe-area and responsive-layout changes belong to the parallel layout task.
