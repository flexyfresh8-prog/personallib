<div align="center">

# 💧 LiquidGlass UI

**A premium Liquid Glass GUI library for Roblox — inspired by Apple's design language.**

Translucent glass surfaces · fluid spring physics · specular light sweeps · adaptive themes

`Luau` · zero external assets · mouse + touch + gamepad · 5 built-in themes

</div>

---

## ✨ Highlights

| System | What you get |
|---|---|
| **Glass design** | Layered translucent panels, luminous borders, inner highlights, soft layered shadows, glass-shading gradients, top-edge light catch |
| **Animation engine** | Centralized `Animator` — TweenService tweens with conflict cancellation + true spring simulations (retargetable), all quality/reduced-motion aware |
| **Signature moments** | Windows materialize from a luminous point, light sweeps across hovered cards, toasts glide and stack, dropdowns unfold with staggered items, tab indicator springs between tabs |
| **Window manager** | Drag with restrained momentum + magnetic edge snapping, resize grips, minimize-to-pill, maximize/restore, multi-window z-order focus, compact sidebar, mobile auto-fit |
| **Components** | 20+ components across Navigation / Input / Display / Feedback / Advanced — see the table below |
| **Performance** | Quality tiers (`High / Balanced / Low`), reduced-motion mode, pooled effects, weak-keyed animation registries, full `Destroy()` cleanup |

## 📦 Components

- **Navigation** — Animated tabs w/ spring indicator · floating glass sidebar · compact mode
- **Input** — Toggle switches · sliders · text inputs · search fields · dropdowns · multi-select · color picker · keybinds
- **Display** — Glass cards · paragraphs · sections · animated dividers · badges · progress bars · segmented progress rings · image panels · tooltips
- **Feedback** — Toast notifications · notification center · confirmation dialogs · alerts · loading overlay (orbiting particles + pulsing ring)
- **Advanced** — Context menus · command palette (Ctrl+K) · dock · floating action button · radial menu

## 🚀 Quick Start

### Loadstring (single file)

```lua
local LiquidGlass = loadstring(game:HttpGet("YOUR_RAW_URL_TO_build/LiquidGlass.lua"))()
```

> The canonical loadstring lives in this repository's description.
> **Note:** this repo is private — the raw URL must include your GitHub token
> (as the description's loadstring does). Treat that URL as a secret.
> Making the repo public lets you drop the token from the URL.

### Roblox Studio (ModuleScript)

1. In `ReplicatedStorage`, create a `ModuleScript` named **LiquidGlass**.
2. Paste the contents of [`build/LiquidGlass.lua`](build/LiquidGlass.lua) into it.
3. In `StarterPlayer > StarterPlayerScripts`, create a `LocalScript` and paste [`src/Demo/DemoClient.client.luau`](src/Demo/DemoClient.client.luau) (or your own code):

```lua
local LiquidGlass = require(game:GetService("ReplicatedStorage").LiquidGlass)
```

### Rojo

```bash
rojo serve default.project.json   # src/ maps into ReplicatedStorage + StarterPlayerScripts
```

## 💻 Usage

```lua
local LiquidGlass = require(...)

local Window = LiquidGlass:CreateWindow({
    Title = "LiquidGlass",
    Subtitle = "Premium Interface",
    Size = UDim2.fromOffset(720, 480),
    Theme = "Midnight",          -- Midnight | Arctic | Aurora | Sunset | Obsidian
    AnimationStyle = "Spring",
})

local Tab = Window:CreateTab({ Name = "General", Icon = "⌂" })

Tab:CreateButton({
    Name = "Example Button",
    Description = "A fluid animated button",
    Callback = function()
        print("Clicked!")
    end,
})

Tab:CreateToggle({
    Name = "Enable Feature",
    Default = false,
    Callback = function(value) print(value) end,
})

Tab:CreateSlider({
    Name = "Intensity",
    Min = 0, Max = 100, Default = 50,
    Callback = function(value) print(value) end,
})

Tab:CreateDropdown({
    Name = "Select Mode",
    Options = { "Performance", "Balanced", "Quality" },
    Default = "Balanced",
    Callback = function(value) print(value) end,
})

Window:Notify({
    Title = "LiquidGlass",
    Description = "Everything is running smoothly.",
    Duration = 4,
})
```

**Default toggle key:** `RightShift` · **Command palette:** `Ctrl + K`

## 🎨 Theming

```lua
Window:SetTheme("Aurora")                      -- live re-tint, everything transitions
Window:SetAccent(Color3.fromRGB(255, 120, 90)) -- override accent instantly

LiquidGlass:RegisterTheme("Nebula", {
    Background = Color3.fromRGB(12, 10, 24),
    Accent = Color3.fromRGB(180, 120, 255),
    Accent2 = Color3.fromRGB(80, 200, 255),
    -- any key you omit inherits Midnight
})
Window:SetTheme("Nebula")
```

Every color in the UI is registered to a theme key — switching themes tweens the entire interface. See [docs/THEMES.md](docs/THEMES.md).

## ⚙️ Configuration

```lua
LiquidGlass:Configure({
    Quality = "High",          -- "High" | "Balanced" | "Low"
    ReducedMotion = false,     -- accessibility: disables every animation
    DragMomentum = true,
    ShowFPS = false,
    ToggleKey = Enum.KeyCode.RightShift,
    Animation = { Speed = 1 }, -- global duration multiplier
})
```

## 🧹 Cleanup

Every object exposes `:Destroy()`. Windows disconnect all connections, kill all
springs/tweens, destroy tabs, controls and overlays:

```lua
Window:Destroy()
LiquidGlass:DestroyAll()
```

## 📚 Documentation

- [docs/API.md](docs/API.md) — complete API reference
- [docs/INSTALL.md](docs/INSTALL.md) — Studio manual setup + Rojo + loadstring
- [docs/THEMES.md](docs/THEMES.md) — theme keys & customization
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — quality tiers & cleanup strategy

## 🗂 Repository Layout

```
src/LiquidGlass/            modular library (Rojo-ready)
  init.luau                 entry point
  Window.luau               window manager
  Tab.luau                  tab + component registry
  Notify.luau               toasts + notification center
  Core/                     Config · Themes · Util · Spring · Animator · Icons · Elements
  Components/               Controls · Select · Input · Display · Feedback · Advanced
  Effects/                  Shine (specular sweeps)
src/Demo/                   demo LocalScript showcasing everything
build/LiquidGlass.lua       generated single-file bundle (loadstring-ready)
tools/build.py              bundler + syntax validator
docs/                       API · INSTALL · THEMES · PERFORMANCE
```

## ⚠️ Notes

- Glass effects are **simulated** with layered Roblox UI instances (gradients,
  strokes, highlights) — no fake backdrop-blur promises.
- No external image assets are required anywhere. Icons are vector-drawn or glyphs.
- Designed for legitimate Roblox Studio development and experiences.

## 📄 License

MIT — see [LICENSE](LICENSE).
