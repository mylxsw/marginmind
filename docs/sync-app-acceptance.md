# 应用回归验收记录

固定起点 `dd592fdf` 的完整应用套件：1907 通过、100 失败、69 跳过（256 个测试文件）。所有初始失败均与本 PR 已合入的 `main=0e4543c8` 在独立工作树按同名用例对照；89 项在 main 同样失败，11 项只在 PR 失败。不能把早期 `cac2ef0d` 的历史记录当作本次判断依据。

修复后的最终定向套件 155 + 4 = 159 项通过。原始 100 项失败中，37 项已由最终套件验证通过，余下 63 项均在当前合入 main 复现；它们没有在最终源码上重跑，尚不能宣称完整 app/CI 全绿。表中“main 同样失败”是同名用例复现，不意味着每项都已定位为产品缺陷。

| 文件 | 初始失败 | main 同样失败 | 修复后验证通过 | 尚未闭环 |
| --- | ---: | ---: | ---: | ---: |
| `adaptive_layout_test.dart` | 10 | 10 | 0 | 10 |
| `ai_task_settings_test.dart` | 1 | 1 | 0 | 1 |
| `app_icon_test.dart` | 1 | 1 | 1 | 0 |
| `assistant_answer_ui_test.dart` | 1 | 1 | 0 | 1 |
| `assistant_composer_ui_test.dart` | 3 | 3 | 0 | 3 |
| `assistant_quick_actions_test.dart` | 1 | 1 | 0 | 1 |
| `assistant_settings_test.dart` | 1 | 1 | 0 | 1 |
| `assistant_settings_ui_test.dart` | 5 | 4 | 1 | 4 |
| `assistant_stage3_test.dart` | 1 | 1 | 0 | 1 |
| `assistant_ui_test.dart` | 1 | 1 | 0 | 1 |
| `beta_features_test.dart` | 1 | 1 | 0 | 1 |
| `document_formats_test.dart` | 1 | 1 | 1 | 0 |
| `document_map_navigation_test.dart` | 2 | 2 | 0 | 2 |
| `document_translation_assembly_test.dart` | 1 | 1 | 0 | 1 |
| `highlight_toolbar_test.dart` | 2 | 2 | 0 | 2 |
| `ink_test.dart` | 1 | 1 | 1 | 0 |
| `inline_edit_test.dart` | 2 | 2 | 0 | 2 |
| `ipad_adaptation_test.dart` | 3 | 2 | 1 | 2 |
| `map_generation_failure_layout_test.dart` | 1 | 1 | 0 | 1 |
| `map_keyboard_test.dart` | 1 | 1 | 0 | 1 |
| `map_style_test.dart` | 1 | 1 | 0 | 1 |
| `map_task_assembly_test.dart` | 1 | 1 | 0 | 1 |
| `map_update_test.dart` | 5 | 4 | 1 | 4 |
| `mobile_polish_test.dart` | 2 | 2 | 0 | 2 |
| `multiple_maps_test.dart` | 2 | 1 | 2 | 0 |
| `note_organizer_factory_test.dart` | 1 | 1 | 0 | 1 |
| `note_route_interaction_test.dart` | 2 | 2 | 0 | 2 |
| `note_workspace_test.dart` | 2 | 2 | 0 | 2 |
| `phone_sidebar_regression_test.dart` | 1 | 0 | 1 | 0 |
| `quick_task_assembly_test.dart` | 1 | 1 | 0 | 1 |
| `reader_chrome_test.dart` | 2 | 2 | 0 | 2 |
| `reading_rebuild_test.dart` | 1 | 0 | 1 | 0 |
| `reflow_advanced_test.dart` | 4 | 0 | 4 | 0 |
| `right_panel_test.dart` | 1 | 1 | 0 | 1 |
| `source_navigation_test.dart` | 18 | 18 | 18 | 0 |
| `stats_test.dart` | 1 | 1 | 0 | 1 |
| `task_runtime_assembly_test.dart` | 1 | 1 | 0 | 1 |
| `translation_lifecycle_test.dart` | 1 | 0 | 1 | 0 |
| `translation_paragraph_test.dart` | 2 | 2 | 0 | 2 |
| `workspace_chrome_test.dart` | 1 | 1 | 0 | 1 |
| `workspace_history_controls_test.dart` | 3 | 3 | 3 | 0 |
| `workspace_layout_test.dart` | 1 | 1 | 0 | 1 |
| `workspace_sidebar_test.dart` | 1 | 1 | 0 | 1 |
| `workspace_tab_strip_test.dart` | 2 | 2 | 0 | 2 |
| `workspace_tabs_test.dart` | 1 | 1 | 1 | 0 |
| `workspace_test.dart` | 2 | 2 | 0 | 2 |

11 项 PR 独有失败覆盖：全文翻译启动竞态、四项对照/翻译资源订阅生命周期、不可变生成记录的条件撤销、手机侧栏空组、平板键盘下设置溢出，以及脑图等值对象断言、真实文件阅读测试时序、设置新增标签断言。翻译、撤销、侧栏及设置布局修复生产行为，其余三类保持实际业务断言并更新测试。

浏览器验收使用真实 release Web 产物、Chrome 和可访问控件操作：PDF 导入、创建节点、刷新后读取持久内容与导出。修复 smoke 脚本以跟随当前创建表单和快捷键可访问名称；未注入替代应用逻辑。

仍未闭环用例（保持可追溯，不静默跳过或重录截图）：

- `assistant_quick_actions_test.dart`: unconfigured AI opens setup locally without sending
- `quick_task_assembly_test.dart`: production quick factories persist runs and send off on initial, HTTP retry and repair
- `reader_chrome_test.dart`: sidebar commands with no room for it find in the sidebar brings it back and focuses the search field
- `reader_chrome_test.dart`: sidebar commands with no room for it a hidden sidebar is shown by the same commands in a wide window
- `note_route_interaction_test.dart`: no default: selecting the admitted override enables AI and forwards it without global writes
- `note_route_interaction_test.dart`: clear, unknown and service invalidation revoke execution; restoring the selected route enables it again
- `workspace_chrome_test.dart`: phone more opens vocabulary and back keeps the workspace pane
- `stats_test.dart`: study set statistics use a reusable content tab that switches and closes
- `highlight_toolbar_test.dart`: highlight menu map and delete linked=false (variant: TargetPlatform.macOS)
- `highlight_toolbar_test.dart`: highlight menu map and delete linked=true (variant: TargetPlatform.macOS)
- `assistant_ui_test.dart`: composer: IME, shift-return, slash menu, @ menu and automatic chips
- `map_task_assembly_test.dart`: production map factories resolve bindings, freeze children, persist partials, and reject unknown profiles
- `workspace_test.dart`: tags open a content view independently of sidebar search
- `workspace_test.dart`: sidebar search filters sections and documents open as tabs
- `right_panel_test.dart`: right panel assistant preserves panes from every origin and keeps manual layout changes
- `note_organizer_factory_test.dart`: unknown profile blocks production before dispatch
- `map_style_test.dart`: style popover in the map pane a click outside closes the popover and ends the preview
- `mobile_polish_test.dart`: iPhone landscape 874×402: library title fits and search still filters
- `mobile_polish_test.dart`: Android landscape: library title fits and search still filters
- `note_workspace_test.dart`: note source closes back to retained note at Size(393.0, 852.0) (variant: TargetPlatform.iOS)
- `note_workspace_test.dart`: note source closes back to retained note at Size(852.0, 393.0) (variant: TargetPlatform.iOS)
- `beta_features_test.dart`: Beta features are hidden by default and shown with Beta badge when enabled
- `document_map_navigation_test.dart`: opening generation settings does not start admission; routed preview displays setup
- `document_map_navigation_test.dart`: unconfigured banner new map opens settings instead of generating
- `task_runtime_assembly_test.dart`: production assembly uses guarded SDK HTTP and persists real study-set run envelope
- `translation_paragraph_test.dart`: paragraph failure and hover toolbar golden light
- `translation_paragraph_test.dart`: paragraph failure and hover toolbar golden dark
- `ai_task_settings_test.dart`: settings › AI features narrow sheet: two-line rows, no overflow, menu becomes an action sheet (variant: TargetPlatform.iOS)
- `workspace_tab_strip_test.dart`: touch close controls stay visible and reachable at 500.0
- `workspace_tab_strip_test.dart`: touch close controls stay visible and reachable at 834.0
- `adaptive_layout_test.dart`: iPhone landscape 874×402: every screen lays out without overflow
- `adaptive_layout_test.dart`: iPad ⅔ 684×1032: every screen lays out without overflow
- `adaptive_layout_test.dart`: iPad mini 744×1133: every screen lays out without overflow
- `adaptive_layout_test.dart`: iPad Pro 13" portrait 1032×1376: every screen lays out without overflow
- `adaptive_layout_test.dart`: iPad Pro 13" landscape 1376×1032: every screen lays out without overflow
- `adaptive_layout_test.dart`: desktop 1280×800: every screen lays out without overflow
- `adaptive_layout_test.dart`: desktop 960×600: every screen lays out without overflow
- `adaptive_layout_test.dart`: touch windows iPad portrait: source above map, sidebar drawer and companion panel
- `adaptive_layout_test.dart`: touch windows iPhone: one pane at a time with a top switch and thumb dock
- `adaptive_layout_test.dart`: touch windows a tablet keeps stable target sizes while switching between trackpad and finger
- `workspace_layout_test.dart`: reader controls are compact; progress appears on hover and divider restores panes
- `map_keyboard_test.dart`: macOS menu lists shortcuts, dispatches commands and protects text focus (variant: TargetPlatform.macOS)
- `assistant_stage3_test.dart`: the root menu organizes or quizzes the whole map
- `assistant_settings_ui_test.dart`: credential recovery opens Model Settings and uses its save flow
- `assistant_settings_ui_test.dart`: the settings link keeps the selected service when providers are shared
- `assistant_settings_ui_test.dart`: new service → key → fetch models → enable → default → listed in the model menu
- `assistant_settings_ui_test.dart`: an unconfigured assistant routes to models and updates after setup
- `document_translation_assembly_test.dart`: document translation freezes its function binding and reopens real disk results through SDK HTTP
- `assistant_answer_ui_test.dart`: in the panel entries are icons only; the header buttons sit at the right; page chips lead with the page
- `map_generation_failure_layout_test.dart`: large-text keeps long diagnostics scrollable and actions reachable
- `assistant_composer_ui_test.dart`: model menu stays above its button at window width 1000.0
- `assistant_composer_ui_test.dart`: model menu stays above its button at window width 1600.0
- `assistant_composer_ui_test.dart`: losing credential access keeps existing answers and page links usable
- `ipad_adaptation_test.dart`: tablet split grip and compact tools light
- `ipad_adaptation_test.dart`: tablet split grip and compact tools dark
- `assistant_settings_test.dart`: production factory opens study-set documents independently of question focus
- `map_update_test.dart`: update sheet keeps close and actions visible with long sources at Size(320.0, 640.0)
- `map_update_test.dart`: update sheet keeps close and actions visible with long sources at Size(402.0, 874.0)
- `map_update_test.dart`: credentials are requested only on preview, missing model stays in form
- `map_update_test.dart`: phone review leaves canvas visible above a bottom panel
- `inline_edit_test.dart`: review fixes: switching fields, menu commands, hidden map
- `inline_edit_test.dart`: E-03 input methods Enter picks a candidate while pinyin is composing
- `workspace_sidebar_test.dart`: footer add menu imports documents and creates maps from the review tab
