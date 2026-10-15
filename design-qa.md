# Design QA

## Comparison target

- Source visual truth: `/Users/maksimversinin/Downloads/ChatGPT Image 21 сент. 2026 г., 18_19_48.png`
- Marker-detail source: `/var/folders/d3/lr0w0ryd43j2djvnnwd5sp4m0000gn/T/codex-clipboard-b54fac20-dd55-46a8-a99b-7e0636cc4f93.png`
- Implementation: `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-controls-v2.png`
- Full-view comparison: `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-comparison-v2.png`
- Focused interaction evidence:
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-recording-v2.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-filters-500.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-selected-route.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/map-settings.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/marker-detail-updated.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/marker-main-map-placement.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/marker-edit-photos.png`
  - `/Users/maksimversinin/XCodeProjects/quadrofriends/artifacts/route-detail-no-top-share.png`
- Device and state: iPhone 17 Pro simulator, iOS 26.3, map and route-detail flows, auto theme rendered in light appearance.
- Source pixels: 1535 × 1024; the first map concept was cropped to 306 × 590.
- Implementation pixels: 1206 × 2622, corresponding to a 402 × 874 point viewport at 3× density.
- Normalization: source and implementation were independently aspect-fitted onto 400 × 700 canvases, then placed side by side in an 800 × 700 comparison image. The different device aspect ratios were preserved rather than stretched.

## Findings

- P0: none.
- P1: none.
- P2: none remaining.
- P3: the iOS 26 native tab bar and materials are more translucent than the flatter chrome in the reference. This is intentional so the implementation follows current platform behavior and accessibility settings.

## Required fidelity surfaces

- Fonts and typography: native San Francisco hierarchy is consistent; the map title, recording metrics, filter labels, and compact control labels remain readable without unintended wrapping or truncation.
- Spacing and layout rhythm: every map control is a 58 pt circle. Search, recording, zoom, and location share the same trailing alignment; map settings and location use equal lower edge insets. No route card obstructs the map.
- Colors and visual tokens: olive primary controls and the orange idle recording control preserve the source direction; recording switches to a red stop state while retaining its size.
- Image quality and asset fidelity: supplied route photographs remain sharp and correctly cropped; MapKit renders the map and route geometry natively; SF Symbols are used for all standard controls.
- Copy and content: Russian labels match the requested search, filtering, recording, location, map-style, and theme concepts. Search and detail views use the same five rating criteria and values.

## Interaction verification

- Search opens as a centered overlay with one primary text field.
- Live text input updates the route list and map annotations.
- Distance supports 25–500 km plus a final unrestricted value; time and completed-count filters are interactive.
- Rating filters use difficulty, mud, fields, forest, and scenery — the same criteria shown on route detail screens.
- Completed count uses a compact numeric text field; an empty value means no restriction.
- Selecting a result closes the overlay, centers the map, swaps to the selected route path and marker, and presents an “Открыть маршрут” button without a route card.
- “Открыть маршрут” navigates to the selected route detail screen.
- Route recording starts immediately; the fixed-size button changes to a red stop icon, while a bottom summary shows elapsed time, distance, and elevation gain.
- Zoom in, zoom out, and center-on-user controls update the map camera.
- Scheme, satellite, and hybrid map styles are selectable.
- Day, night, and auto modes update the whole application through the shared color scheme.
- The marker detail screen has no “Построить маршрут сюда” action; the former ellipsis action is a pencil that opens a populated edit form.
- New markers start at the current geolocation on the main map. The underlying map remains interactive above the medium editor sheet; dragging the marker updates the displayed coordinate before save.
- The client intentionally performs no 1 km distance calculation or rejection. The backend owns the route-distance validation for the submitted coordinate.
- The route detail toolbar contains only the bookmark action; route sharing remains available in the lower action bar.
- Marker editing supports adding multiple images from the photo picker and deleting individual images. Changes are committed only by the save action.
- The generic iOS build and the iPhone 17 Pro simulator build pass.

## Comparison history

1. Initial pass found a P2 layout issue: with filters expanded, the selected-route card reduced the available overlay height and clipped the first search result.
2. Fix: hide the selected-route card while search is open.
3. Post-fix evidence: `artifacts/map-search-filters.png` shows multiple complete result rows, with filters, close action, and tab bar visible without overlap.
4. The current iteration removed the route card entirely and replaced mixed native control sizes with a shared 58 pt component aligned to 16 pt edge insets.
5. `artifacts/map-recording-v2.png` confirms the recording button keeps its dimensions in the red stop state and that all three live metrics fit above the tab bar without overlap.
6. Search filters were aligned with the route-detail rating model, the completed-count stepper was replaced by numeric input, and distance was extended through 500 km with a final unrestricted position.
7. `artifacts/map-selected-route.png` confirms the selected track, photo marker, and route-opening action appear without restoring the removed route card.
8. The marker-detail iteration intentionally removes the green route-building CTA and replaces the ellipsis toolbar action with an edit pencil.
9. `artifacts/marker-detail-updated.png` confirms the simplified detail screen; the pencil was also exercised and opened the pre-filled edit form.
10. The previous creation iteration used a mini-map inside the sheet; it was replaced by placement directly on the main map.
11. The initially proposed 1 km client-side guard was removed after the product decision to validate that constraint on the backend.
12. The first full-resolution marker-detail capture exposed a P2 horizontal overflow: unconstrained photo thumbnails widened the vertical scroll content and clipped the leading edge of copy.
13. Fix: constrain the photo row to the available width. `artifacts/marker-detail-updated.png` confirms the title, description, and all thumbnails stay within the viewport.
14. `artifacts/marker-main-map-placement.png` confirms the new marker appears at the current location on the main map while the data-entry sheet remains open below it. A drag test changed the live coordinate from `59.98800, 30.19900` to `59.99105, 30.17290`.
15. `artifacts/route-detail-no-top-share.png` confirms the upper share action is removed while the lower “Поделиться” flow remains.
16. `artifacts/marker-edit-photos.png` confirms per-photo delete controls and the add-photo action. Removing one image and saving reduced the detail gallery from three images to two.

## Open questions

- None.

## Implementation checklist

- [x] Remove the hamburger control.
- [x] Keep search as the only top-right navigation action.
- [x] Use one enlarged size for every floating map control.
- [x] Align the right-side controls and lower corner controls to shared edge insets.
- [x] Remove the selected-route card from the map.
- [x] Keep the recording button size fixed while changing its color and icon.
- [x] Show time, distance, and elevation gain while recording.
- [x] Support distance through 500 km and an unrestricted value.
- [x] Match search rating filters to all five route rating criteria.
- [x] Replace the completed-count stepper with compact numeric input.
- [x] Show the selected route on the map and open its detail screen from a dedicated button.
- [x] Place zoom controls at center-right.
- [x] Place location at bottom-right.
- [x] Place map and app-theme settings at bottom-left.
- [x] Remove the route-building action from the marker detail screen.
- [x] Replace the marker overflow action with a working edit pencil.
- [x] Start a new marker at the current position and allow free map dragging.
- [x] Place and move the draft marker on the main map rather than an embedded mini-map.
- [x] Pass the selected marker coordinate for backend validation without duplicating the 1 km rule on the client.
- [x] Remove the upper share action from route details while keeping the lower sharing flow.
- [x] Add and remove photos while editing a marker.
- [x] Verify all requested states in Simulator.

final result: passed
