# UI conventions

Screens are ports of the RN app (`../VibeCallingFrontEnd`). The RN screen is the spec for design, copy and behaviour.

The references for how things are built here:
- `lib/app/homescreen/` (Home shell, Discover feed)
- `lib/app/authscreen/` (login, onboarding)
- `lib/app/listingflow/widgets/host_grid_card.dart`

## Structure

- **Feature folder:** each feature lives in its own folder (e.g. `lib/app/listingflow/profile/`).
- **`helper/`:** inside the feature folder, for logic: controllers, pure mapping and formatting, layout math. Widgets stay thin.
- **File size:** no file over 500 lines. Split by section (header, gallery, reviews, actions…).
- **Shared widgets:** one generic enough for other features goes in `lib/app/component/`. Otherwise keep it in the feature folder.

## Building blocks (use these, don't re-create them)

| Need | Use |
| --- | --- |
| Text | `CText('ns:key')` for every visible string. Use `CText.raw(...)` only for server data (names, taglines, amounts already formatted). |
| Buttons, inputs, alerts, toasts | `CButton`, `CInput`, `CAlert`, `CToast`, `Pressable` (tap feedback), `CBackButton` |
| Images | `CImage` (always pass `width`, so it decodes at display size) and `CAvatar` |
| First load | `Shimmer` + `SkeletonBox` / `SkeletonLines`. Use a skeleton shaped like the real content, not a spinner. |
| Paged lists | `InfiniteScroll` (pull-to-refresh, load-more, footer) with lazy slivers (`SliverList.builder`, `SliverVariedExtentList`) |
| Errors and empty states | `CStateView.error(context, e, onRetry:)`, `CStateView.empty(...)`, `QueryView` |
| Sizes | `16.ms` / `moderateScale(16)`. Colors from `context.colors` and `AppColors`/`BrandColors`/`StatusColors`. |
| Data | the hooks in `lib/app/api/<feature>/*_queries.dart` (fquery). Never `ApiClient` in a widget. |

## Performance (120 fps, no wasted rebuilds)

- **State:** `HookWidget` + hooks. Keep local state small and split it: one `useState` / `ValueNotifier` per independent piece. Wrap the part that changes in a `ValueListenableBuilder`, not the whole screen.
- **Scrolling:** nothing calls `setState` on scroll. Scroll-driven effects read `ScrollMetrics` (see `NavbarCollapse`).
- **Lists:** always lazy. Never build a `Column` of hundreds of rows.
- **Fixed heights:** give rows a fixed height when the design has one (`itemExtent`, `SliverVariedExtentList`).
- **Repaints:** wrap continuously animating pieces in a `RepaintBoundary`.
- **No live blur in scrolling content:** no `BackdropFilter` there.
- **Memoize:** derive data with `useMemoized(…, [deps])`.
- **Constructors:** `const` wherever possible.
- **Sheets and modals:** `showModalBottomSheet` / `showGeneralDialog` with simple fade or slide transitions.

## Errors

- **Queries:** use `QueryView` or check `isLoading` / `isError` / `data` yourself.
  - Error before any data: `CStateView.error(...)` with retry.
  - Failed background refetch: keep showing the data.
- **Actions** (mutations, async taps):
  - `CAlert.error(e)` for blocking failures, `CToast.error(e)` for light ones.
  - Disable the trigger while it runs (`loading:` on `CButton`).

## i18n

- **Key files:** keys go in the feature's namespace file, `assets/i18n/{en,hi}/<ns>.json`.
- **Languages:** natural Hindi (Devanagari), with the same keys as English. Brand names stay Latin.
- **No English in widgets:** no hard-coded English strings in widgets.

## Tests

- **Location:** widget tests go in `test/ui/<feature>_test.dart`.
- **Fake backend:** use the fake-Dio-adapter pattern of `test/auth/login_screen_test.dart`:
  - prefs, secure storage and `PackageInfo` mocks;
  - a phone viewport plus `Scale.update(const Size(390, 844))`;
  - pump in 50 ms steps;
  - at the end, unmount and pump 6 minutes for fquery's GC timers.
