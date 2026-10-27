# Themes

LiquidGlass ships five adaptive themes. Every color in the UI is registered to
a **theme key**, so switching themes tweens the whole interface live — surfaces,
strokes, text, accents, gradients, shadows.

## Built-in themes

| Theme | Mood | Accent | Accent2 |
|---|---|---|---|
| `Midnight` | Deep navy glass (default) | `rgb(92,158,255)` | `rgb(148,122,255)` |
| `Arctic` | Light frosted glass | `rgb(0,120,255)` | `rgb(96,84,255)` |
| `Aurora` | Teal bioluminescence | `rgb(52,224,196)` | `rgb(122,138,255)` |
| `Sunset` | Warm dusk | `rgb(255,118,92)` | `rgb(255,176,84)` |
| `Obsidian` | Monochrome noir | `rgb(235,235,242)` | `rgb(150,150,162)` |

```lua
Window:SetTheme("Aurora")
```

## Theme keys

Any key may be overridden. Missing keys inherit from **Midnight**.

### Surfaces
- `Background` — window panel base
- `Surface` — cards, sidebar, dropdown panels
- `SurfaceHigh` — hovered/raised surfaces
- `Track` — recessed inputs, slider tracks, toggle tracks
- `Overlay` — dimming layers (dialogs, palette, radial)

### Lines & light
- `Stroke` — outer luminous borders
- `InnerStroke` — card borders
- `Divider` — separators
- `Highlight` + `HighlightT` — top glass light-line color/transparency
- `ShadeTop` / `ShadeBottom` — glass shading gradient (multiplies backgrounds)

### Text
- `TextPrimary` · `TextSecondary` · `TextMuted`

### Color system
- `Accent` · `Accent2` — fills, fills-gradients, focus rings, progress
- `OnAccent` — text/icons placed on accent fills
- `Success` · `Danger` · `Warning` — status variants
- `Knob` — toggle/slider thumbs
- `Scroller` — scrollbar accents
- `Shadow` — drop shadow layers
- `Dark` (boolean) — marks dark themes

## Custom themes

```lua
LiquidGlass:RegisterTheme("Nebula", {
    Name = "Nebula",
    Background = Color3.fromRGB(12, 10, 24),
    Surface = Color3.fromRGB(22, 18, 40),
    SurfaceHigh = Color3.fromRGB(30, 25, 54),
    Accent = Color3.fromRGB(180, 120, 255),
    Accent2 = Color3.fromRGB(80, 200, 255),
    OnAccent = Color3.fromRGB(14, 10, 26),
    ShadeBottom = Color3.fromRGB(150, 140, 190),
})

Window:SetTheme("Nebula")
-- or per-window:
LiquidGlass:CreateWindow({ Theme = "Nebula" })
```

One-off overrides are also allowed without registering:

```lua
LiquidGlass:CreateWindow({
    Theme = { Background = Color3.fromRGB(8, 8, 12) },  -- merged over Midnight
})
```

## Per-window accent override

```lua
Window:SetAccent(Color3.fromRGB(255, 120, 90), Color3.fromRGB(255, 176, 84))
```

Accent-driven elements (glow stroke, toggles, sliders, progress fills,
selection bars, radial hub, FAB) transition immediately.
