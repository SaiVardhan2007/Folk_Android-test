# FOLK Tracker: project standards

Every change follows this file. If a rule here is wrong, change the rule first, then the code.

## 1. Where things live (change once, changes everywhere)
| What | Where |
|---|---|
| Colours, fonts, text sizes, **text scale knob** (`kTextScale`), component styles. Status/brand colours that differ in light/dark mode: `context.colors.success / warning / danger / brand / accent` (`AppColors`, a Flutter ThemeExtension). Never use a fixed colour in a screen. | `lib/core/theme.dart` |
| Breakpoints (phone / tablet / laptop), spacing scale (`kGapS..kGapXL`), `ResponsiveGrid` | `lib/core/layout.dart` |
| Shared widgets: `PageBody`, `SectionTitle`, `FieldGrid`, `StatTile`, `StatGrid`, `SheetBody`, `StatusBanner`, `ErrorView`, `AppLogo`, `EventPicker`, `OptionDropdown` | `lib/core/widgets.dart` |
| Data cache + "show saved data then refresh" | `lib/core/cache.dart` (`cachedGet`) |
| HTTP client, errors | `lib/core/api.dart` |
| Refresh timing constants | `lib/core/config.dart` |

Rules:
- Screens never hard-code colours, font sizes, breakpoints or raw spacing. Use theme tokens, `Theme.of(context).textTheme`, `kGap*`, `ResponsiveGrid`.
- A new screen is built from the shared widgets. If a layout is needed twice, it becomes a shared widget first.
- Phone vs tablet/laptop is decided only by `windowClass` / `ResponsiveGrid` (Material 3 window size classes: compact < 600, medium 600-839, expanded >= 840).

## 2. Data (standard offline-first read pattern)
- Reads: `cachedGet` = emit the saved copy at once, then the fresh server answer (Flutter's "stream of local then remote"). Offline, the saved copy stays.
- Saved data is wiped on sign-out.
- Refresh happens: when a screen opens, when the app returns to the foreground, on pull-down, after the user's own action. Never a timer of seconds. The only timer is the 60 s live list on Attendance (`kLiveListRefresh`). Push (Firebase) is the standard for instant updates later.
- Writes go to the server; a retry is always safe (idempotent IDs / `client_ref`).

## 3. Speed
- Lists with more than a handful of rows use builders (`SliverList` / `ListView.builder`), never `Column` with every row.
- `setState` is local: a keystroke may rebuild only the widget showing it (use small widgets, `ValueNotifier`, `ListenableBuilder`).
- Judge speed only in a **release** build (`flutter run --release`), never debug.

## 4. Branding
- Logo: `assets/images/folk_logo.png` (transparent). In screens use only the `AppLogo` widget. App icon: replace `assets/images/icon_full.png` and `icon_foreground.png`, then run `dart run flutter_launcher_icons`.
- Check new screens in light mode (the default). Dark colours still exist in the theme for later.

## 5. Touch safety and navigation
- The app is always light-themed (`kThemeMode` in `lib/core/config.dart`); the phone's dark mode is ignored. Switch to `ThemeMode.system` to follow the phone.
- Bottom navigation is `AppBottomBar` (shared widget): each tab is ONE bordered button (icon + label), selected tab filled saffron. Never use the stock NavigationBar for it.
- The Call button dials immediately on tap (the user chose no confirmation pop-up). Destructive actions such as deleting or removing still ask for confirmation.
- Compact statistics use `StatStrip` + `MiniStat` (one row of squares); larger ones use `StatGrid` + `StatTile`.

## 6. Process (every few changes)
1. `dart format lib test`  2. `flutter analyze` (must be clean)  3. `flutter test`  4. re-read what changed against this file.
