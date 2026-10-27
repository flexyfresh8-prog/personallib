# Installation Guide

Three ways to install LiquidGlass. Pick one.

---

## Option A — Loadstring (single file)

The repository description contains the canonical loadstring. It points at
`build/LiquidGlass.lua` on the `main` branch.

```lua
local LiquidGlass = loadstring(game:HttpGet("https://raw.githubusercontent.com/flexyfresh8-prog/personallib/main/build/LiquidGlass.lua"))()
```

> **Security note:** this repository is public, so the loadstring URL is clean
> and carries no token. Never embed a GitHub token in a loadstring URL you
> share — anyone holding it gets your account access. If a token ever leaks,
> revoke it at github.com/settings/tokens immediately.

## Option B — Roblox Studio (manual, no plugins)

1. **Library module**
   - `ReplicatedStorage` → insert a **ModuleScript**, name it exactly `LiquidGlass`.
   - Paste the full contents of [`build/LiquidGlass.lua`](../build/LiquidGlass.lua).
2. **Demo / your script**
   - `StarterPlayer → StarterPlayerScripts` → insert a **LocalScript**.
   - Paste [`src/Demo/DemoClient.client.luau`](../src/Demo/DemoClient.client.luau) (demo) or write your own:
     ```lua
     local LiquidGlass = require(game:GetService("ReplicatedStorage"):WaitForChild("LiquidGlass"))
     ```
3. Press **Play**. RightShift toggles the window.

Prefer the modular tree in Studio? Create this hierarchy of ModuleScripts/Folders
with the matching files from `src/`:

```
ReplicatedStorage
└── LiquidGlass            (ModuleScript  ← src/LiquidGlass/init.luau)
    ├── Window             (ModuleScript  ← Window.luau)
    ├── Tab                (ModuleScript  ← Tab.luau)
    ├── Notify             (ModuleScript  ← Notify.luau)
    ├── Core               (Folder)
    │   ├── Config / Themes / Util / Spring / Animator / Icons / Elements
    ├── Components         (Folder)
    │   ├── Controls / Select / Input / Display / Feedback / Advanced
    └── Effects            (Folder)
        └── Shine
```

## Option C — Rojo (recommended for development)

1. Install [Rojo](https://rojo.space) (VS Code extension or CLI 7+).
2. Clone this repository.
3. `rojo serve default.project.json` from the repo root.
4. Connect from Rojo in Studio. You get:
   - `ReplicatedStorage.LiquidGlass` — the full modular source tree
   - `StarterPlayerScripts.DemoClient` — the demo LocalScript

Rebuild the single-file bundle after editing `src/`:

```bash
python3 tools/build.py
```

The bundler also validates syntax for every module and the bundle, and it
resolves `require(script.Parent.Core.Util)` style requires into string keys —
the same source tree works natively in Rojo **and** inside the bundle.

## Executors

Loadstring works in executor environments as well; the module handles
`gethui()` / `CoreGui` parenting automatically and falls back to `PlayerGui`
where needed. The demo body can be pasted below the `loadstring(...)` line.

---

## Verification checklist

- [ ] Window materializes with a glow burst on play
- [ ] `RightShift` hides/shows the window
- [ ] Dragging the title bar works; release near a screen edge snaps it
- [ ] Bottom-right grip resizes the window
- [ ] Minimize collapses to a pill; clicking it restores
- [ ] `Ctrl + K` opens the command palette
- [ ] Right-click inside the window opens the context menu
- [ ] Theme dropdown re-tints the entire UI live
