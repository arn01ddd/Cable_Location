# Release audit: 2.2.1

Scope: navy dark appearance, text and control contrast, native UI states, session
regressions, dependency advisories, and Mac release packaging.

## Findings addressed

- Fixed light backgrounds in destination, session, secondary buttons, and
  Diagnostics. The native workspace now explicitly uses dark appearance.
- Replaced green/light-theme tokens with near-black, navy, pale text, and blue
  accents. Status, validation, and recovery use distinct readable colors.
- Separated primary button text and fill colors. Reusing the normal text color
  as the fill would produce incorrect contrast after switching to dark mode.
- Replaced light-theme literals in contrast checks with the actual shared palette
  tokens. Checks now cover 20 text pairs and four control/focus boundaries.
- Strengthened input and enabled secondary-button borders to remain distinguishable
  against dark panels. Disabled actions retain readable labels.

## Verification

- Sixteen backend tests cover coordinate validation, USB-only discovery,
  asynchronous refresh, reconnection, cancellation, and restoration failure.
- Seventy-four native assertions cover 35 shared coordinate cases, action
  availability, device selection, stale/live/restoring status, restoration error
  recovery, session timing, and contrast.
- Normal-text pairs must reach 4.5:1. Input/secondary-control boundaries and focus
  indication must reach 3:1. These checks do not constitute a complete
  accessibility conformance review.
- Native previews cover empty, ready, active, error/Diagnostics, and minimum-size
  layouts. The dark renders are reviewed before release; the workflow retains
  the previews as artifacts.
- Release publication requires a clean dependency advisory scan, backend tests,
  launcher syntax checks, native compilation/checks, preview rendering, signature
  verification, and ZIP checksum verification.

The theme change introduces no backend behavior, dependencies, coordinate
storage, or new network services. Existing keyboard shortcuts and accessibility
labels remain available.

## Limits

No physical iPhone is attached to this environment; automated device services are
mocks. Verify simulated and restored locations in iPhone Maps. The app is ad-hoc
signed without Apple Developer ID notarization. A disconnected cable, closed
lid, crash, or force quit may interrupt restoration.
