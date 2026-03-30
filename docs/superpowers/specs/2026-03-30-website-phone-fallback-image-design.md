# Website Phone Fallback Image

## Goal

Replace the blank pre-launch iPhone state in the website hero with the approved Figma lock-screen image, while keeping the existing phone frame and demo video timing unchanged.

## Context

The website hero currently renders the iPhone screen area as black until the demo enters the verify phase. That behavior lives in `website/src/components/DemoHero/IPhoneFrame.tsx`, where the video is present but hidden until `videoTime >= 0`.

The requested design is a static lock-screen image from Figma node `754:48094`. This is a visual placeholder for the "app not launched yet" phase, not a new interactive screen.

## Design

### Recommended approach

Add the Figma lock-screen as a local image asset in `website/public/` and render it inside the existing screen cutout whenever `videoTime < 0`.

When `videoTime >= 0`, switch back to the existing `demo.mp4` video behavior. The iPhone frame overlay remains unchanged.

### Why this approach

- Matches the approved Figma design exactly.
- Keeps the asset stable and versioned in-repo instead of depending on an expiring remote Figma asset URL.
- Requires only a small, isolated component change.
- Preserves the existing timeline behavior and hero layout.

## Component Changes

### `website/src/components/DemoHero/IPhoneFrame.tsx`

- Add a local fallback image source for the lock-screen artwork.
- Render the fallback image in the same masked screen container used by the video.
- Keep the fallback visible only while `videoTime < 0`.
- Keep the video visible only while `videoTime >= 0`.
- Leave the existing frame overlay image (`iphone-frame.png`) in place.

### `website/src/components/DemoHero/timeline.ts`

No changes. The existing `videoTime = -1` pre-launch state already expresses the required behavior clearly.

## Asset Handling

Add one new static image file under `website/public/` for the lock-screen artwork captured from the approved Figma node. The asset should be sized and cropped to fill the existing phone screen area with `object-cover`, matching the current video behavior.

## Testing

Add a focused component test for `IPhoneFrame` that verifies:

1. The fallback image is rendered for the pre-launch state (`videoTime < 0`).
2. The fallback image is hidden once the demo reaches the video phase (`videoTime >= 0`).
3. The video remains the visible content in the launched state.

## Risks

- If the fallback is implemented as a remote Figma URL, it will expire and break the site. The asset must be stored locally.
- If the fallback and video do not share the same sizing rules, the transition will jump visually. Both should use the same fit and positioning rules.

## Out of Scope

- Rebuilding the Figma lock screen as HTML/CSS.
- Changing the demo timeline or hero layout.
- Adding animation to the pre-launch fallback state.
