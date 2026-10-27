# LiquidGlass API Reference

Library version: **1.0.0**

---

## LiquidGlass (root module)

### `LiquidGlass:CreateWindow(config) -> Window`
Creates and shows a window.

| Config key | Type | Default | Description |
|---|---|---|---|
| `Title` | string | `"LiquidGlass"` | Window title |
| `Subtitle` | string | nil | Dim subtitle shown top-right |
| `Size` | UDim2 | `720 x 480` | Panel size (offsets) |
| `Position` | UDim2 | centered | Only offsets are used |
| `Theme` | string/table | `"Midnight"` | Theme name or override table |
| `Accent` | Color3 | nil | Accent override for this window |
| `Accent2` | Color3 | nil | Secondary accent (gradients) |
| `ToggleKey` | Enum.KeyCode | `RightShift` | Show/hide hotkey |
| `Compact` | boolean | false | Icon-only sidebar |
| `ShowOnCreate` | boolean | true | Play the open animation immediately |
| `CloseBehavior` | string | `"Hide"` | `"Hide"` or `"Destroy"` on X |
| `NotificationCenter` | boolean | true | Show the bell button |

### Other root methods
- `LiquidGlass:Configure(table)` → merge runtime config (deep-merges Window/Animation/Spring/Notify/Tooltips)
- `LiquidGlass:SetQuality("High" | "Balanced" | "Low")`
- `LiquidGlass:SetReducedMotion(boolean)`
- `LiquidGlass:RegisterTheme(name, overridesTable)`
- `LiquidGlass:GetThemeNames() -> {string}`
- `LiquidGlass:Notify(config)` → global toast (outside any window theme)
- `LiquidGlass:GetWindows() -> {Window}`
- `LiquidGlass:DestroyAll()`

---

## Window

### Tabs
- `Window:CreateTab({ Name = "General", Icon = "⌂" }) -> Tab`
  `Icon` accepts a glyph string, an `"rbxassetid://…"` string, or an asset id number.
- `Window:SelectTab(index)`
- `Window:GetTab(nameOrIndex) -> Tab`

### Lifecycle
- `Window:Show()` — materialize-from-a-point open animation
- `Window:Hide()` — glass fade + contract; keeps the window alive
- `Window:Toggle()`
- `Window:Minimize()` — collapses into a floating glass pill
- `Window:Restore()`
- `Window:ToggleMaximize()`
- `Window:Focus()` — raises z-order among windows
- `Window:Destroy()` — full cleanup (connections, springs, tweens, children)

### Properties & theming
- `Window:SetTheme(nameOrTable)` — live re-tint of every registered surface
- `Window:SetAccent(color [, color2])`
- `Window:SetTitle(text)` / `Window:SetSubtitle(text)`
- `Window:SetCompact(boolean)` — toggles the slim icon sidebar

### Systems
- `Window:Notify(config)` — toast + history entry
- `Window:NotificationCenter()` is exposed via the bell button (`LiquidGlass.Notify.ToggleCenter(window)`)
- `Window:Dialog(config)` / `Window:Alert(config)`
- `Window:Loading() -> handle` (`:Show(text?)`, `:Hide()`, `:SetText(text)`, `:Destroy()`)
- `Window:RegisterCommand({ Name, Callback })` — command palette entry
- `Window:GetCommands() -> table` (window commands + auto-registered toggles)
- `Window:CommandPalette()` -> palette handle (`Open/Close/Toggle/Destroy`), bound to `Ctrl+K`
- `Window:CreateContextMenu(target, { Items = { { Name, Callback, Icon? }, { Divider = true } } })`
- `Window:CreateDock({ Items = { { Name, Icon, Callback } } })` -> dock handle
- `Window:CreateFAB({ Icon, Position?, Callback })` -> FAB handle
- `Window:CreateRadialMenu({ Radius?, Items = { { Name, Icon, Callback } } })` -> radial handle (`Open(pos?)`, `Close()`, `Toggle()`)

---

## Components (Tab methods)

Every factory takes a config table and returns a **control object**.
All controls provide `Frame` and `Destroy()`. Where noted they also expose
`Get/Set`, a `Changed` signal, and `Kind`.

### Navigation
- `Tab:CreateSection({ Name })` — accent label with pulsing bar
- `Tab:CreateDivider()` — shimmering gradient separator

### CreateButton(config)
`{ Name, Description?, Tooltip?, Callback }`
Returns: `Clicked` signal, `SetName(text)`.

### CreateToggle(config)
`{ Name, Description?, Tooltip?, Default = false, Callback(value) }`
Returns: `Get()`, `Set(value, silent?)`, `Changed` signal. Toggles auto-register a command palette entry (`"Toggle: <name>"`).

### CreateSlider(config)
`{ Name, Tooltip?, Min, Max, Default, Increment, Suffix?, Callback(value) }`
Returns: `Get()`, `Set(value, silent?)`, `SetRange(min, max)`, `Changed`.

### CreateDropdown(config)
`{ Name, Tooltip?, Options = {…}, Default, Multi = false, Callback(value) }`
Single mode fires the selected value; multi mode fires a `{ [name] = true }` table.
Returns: `Get()`, `Set(value, silent?)`, `Refresh(newOptions)`, `Changed`.

### CreateTextInput(config) / CreateSearchField(config)
`{ Name, Placeholder?, Default?, Callback(text, enterPressed) }`
Returns: `Get()`, `Set(text)`, `Clear()`, `Focus()`, `SetPlaceholder()`, `Changed`, `Submitted` signals. Search fields include a clear button.

### CreateKeybind(config)
`{ Name, Default = Enum.KeyCode.F, Callback() }`
Click the chip, press any key (Esc/Backspace clears).
Returns: `GetBind()`, `SetBind(key)`, `Pressed` signal, `Changed`.

### CreateColorPicker(config)
`{ Name, Default = Color3, Callback(color) }`
Saturation/value square + hue bar, live hex + RGB readout.
Returns: `Get()`, `Set(color, silent?)`, `Changed`.

### Display
- `Tab:CreateCard({ Title?, Content, RichText? })` — glass paragraph; returns `SetTitle`, `SetContent`
- `Tab:CreateBadge({ Text, Variant = "Success"|"Danger"|"Warning"|"Accent"|"Neutral" })` — returns `SetText`, `SetVariant`
- `Tab:CreateProgress({ Name, Default = 0 })` — returns `Get`, `Set(v)`, `Pulse()` (indeterminate)
- `Tab:CreateProgressRing({ Name, Default = 0 })` — segmented dot ring; returns `Get`, `Set(v)`
- `Tab:CreateImagePanel({ Name?, Image, Height?, Caption? })` — returns `SetImage`

### Notifications
`Window:Notify({ Title, Description?, Type = "success"|"error"|"warning"|"info", Duration = 4, Width? })`
`Duration <= 0` keeps the toast until dismissed. Max 5 stack; older ones auto-dismiss.
Returns `{ Dismiss(), Frame }`.

---

## Signals

Signals are lightweight custom objects: `signal:Connect(fn) -> connection`,
`connection:Disconnect()`, `signal:Fire(...)`, `signal:DisconnectAll()`.

## Error handling

- Public setters validate types defensively (e.g. `Set` on ColorPicker checks `typeof(color) == "Color3"`).
- `SetQuality` asserts one of the three valid tiers.
- Component destruction is idempotent; `Window:Destroy()` wraps child destruction in `pcall`.

## Icons

Anywhere an `Icon` is accepted:
- glyph string: `"⌂"`, `"✦"`, `"⚙"`, `"◐"`, `"◈"`, `"⌗"` …
- image: `"rbxassetid://123456"` or `123456`

System icons (check / cross / alert / info / chevron / plus / minus / square / search / dot) are **vector-drawn with frames**, so they never depend on font coverage and they re-tint with themes.
