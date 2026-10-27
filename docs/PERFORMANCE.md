# Performance & Cleanup Strategy

LiquidGlass aims for spectacular visuals **without** melting frame budgets.

## Quality tiers

```lua
LiquidGlass:SetQuality("High")      -- everything
LiquidGlass:SetQuality("Balanced")  -- interactive effects only, no idle loops
LiquidGlass:SetQuality("Low")       -- no decorative effects, instant transitions
LiquidGlass:SetReducedMotion(true)  -- accessibility: kills ALL animation
```

| Feature | High | Balanced | Low / ReducedMotion |
|---|---|---|---|
| Spring & tween motion | ✅ | ✅ | ❌ instant |
| Specular light sweeps | ✅ | ✅ | ❌ |
| Click ripples | ✅ | ✅ | ❌ |
| Staggered card entrance | ✅ | ✅ | ❌ |
| Idle loops (section pulse, divider shimmer, FAB glow, orbit particles) | ✅ | ❌ | ❌ |
| Drag momentum + edge snap | ✅ | ✅ | direct drag |
| Loader orbit particles | ✅ | ❌ | ❌ |
| `Config.T(duration)` | scaled | scaled | forced to 0 |

All effect gates read config **at call time**, so quality can change at runtime
(the demo binds a dropdown to it).

## Rendering discipline

- **No permanent RenderStepped loops.** Idle effects run on `Heartbeat` through
  `Animator.Loop`, only while their owner exists, and are gated by quality.
- **Pointer-driven effects are event-driven** (MouseEnter/Leave), never polled.
- Springs self-disconnect the frame they settle (`|Δ| < precision`).
- Weak-keyed registries (`Animator`) ensure forgotten instances can be GC'd.
- Effects pool their transient instances: the Shine band is created once per
  host and reused; ripples are destroyed on completion.

## Instance budget

A full window (5 tabs, ~40 components) creates roughly:
- one CanvasGroup for the panel + one per toast/dialog (CanvasGroups are capped in count),
- ~1 frame + 2-3 descendants per component,
- zero ImageLabels unless you provide image assets.

CanvasGroup usage is limited to whole-window fades, dialogs, toasts, tooltips —
the elements that benefit most from single-property fades.

## Cleanup strategy

1. **Janitors everywhere** — every widget owns a `Util.NewJanitor()` collecting
   its connections, cleanup functions and child janitors.
2. **Animator.Cancel(instance)** — kills every tween and spring on an instance;
   called by `Destroy()` paths.
3. **Window:Destroy()** —
   1. destroys all tabs (which destroy all controls → janitors run),
   2. disconnects window-level listeners (drag, resize, toggle key, palette),
   3. cancels animations on root/panel,
   4. removes itself from the registry,
   5. destroys the ScreenGui (dropping every remaining instance).
4. **Signals** — custom lightweight signals support `DisconnectAll`; destroyed
   controls leave no live handlers.
5. **Idempotence** — calling `Destroy()` twice is safe (guard flags).

## Mobile / low-end devices

- Small viewports (<720px wide) trigger compact layout, auto-fit sizing, and
  skip resize grips.
- Touch input is a first-class citizen: dragging, sliders, color picker, radial
  menu and context menu all accept `UserInputType.Touch`.
- Set `Balanced` quality on low-end targets to drop every idle loop.
