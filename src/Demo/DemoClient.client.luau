--[[
        LiquidGlass · Demo
        Showcases every major component of the library.

        HOW TO RUN (Roblox Studio):
          Option A (Rojo): default.project.json maps this file to StarterPlayerScripts.
          Option B (manual):
            1. Create a ModuleScript named "LiquidGlass" in ReplicatedStorage and paste
               build/LiquidGlass.lua into it.
            2. Create a LocalScript in StarterPlayerScripts and paste THIS file into it.
          Option C (executor):
            loadstring(game:HttpGet("<raw url to build/LiquidGlass.lua">))() then run the
            demo body below (see README for the exact loadstring).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Resolve the library -----------------------------------------------------------------
local LiquidGlass
do
        local ok = pcall(function()
                LiquidGlass = require(ReplicatedStorage:WaitForChild("LiquidGlass", 5))
        end)
        if not ok or LiquidGlass == nil then
                -- fallback: ModuleScript next to this script
                LiquidGlass = require(script.Parent:WaitForChild("LiquidGlass"))
        end
end

local LocalPlayer = Players.LocalPlayer

-- Window ---------------------------------------------------------------------------------
local Window = LiquidGlass:CreateWindow({
        Title = "LiquidGlass",
        Subtitle = "Premium Interface",
        Size = UDim2.fromOffset(720, 480),
        Theme = "Midnight",
        AnimationStyle = "Spring",
})

Window:RegisterCommand({
        Name = "Cycle theme",
        Callback = function()
                local names = LiquidGlass:GetThemeNames()
                local current = Window._theme.Name
                local index = table.find(names, current) or 0
                Window:SetTheme(names[(index % #names) + 1])
        end,
})

--==========================================================================================
-- TAB: GENERAL
--==========================================================================================
local General = Window:CreateTab({ Name = "General", Icon = "⌂" })

General:CreateSection({ Name = "Welcome" })

General:CreateCard({
        Title = "LiquidGlass UI",
        Content = "A premium glass design system for Roblox. Drag the window by its title bar, "
                .. "resize it from the bottom-right grip, minimize it into a pill, and press "
                .. "RightShift to toggle visibility. Hover anything — light reacts.",
})

General:CreateSection({ Name = "Controls" })

General:CreateButton({
        Name = "Example Button",
        Description = "Fires a fluid animated callback",
        Callback = function()
                print("[LiquidGlass] Button clicked!")
                Window:Notify({ Title = "Hello", Description = "Button pressed.", Type = "success", Duration = 3 })
        end,
})

General:CreateToggle({
        Name = "Enable Feature",
        Description = "Spring-animated switch",
        Default = false,
        Callback = function(value)
                print("[LiquidGlass] Feature:", value)
        end,
})

local intensity = General:CreateSlider({
        Name = "Intensity",
        Min = 0,
        Max = 100,
        Default = 50,
        Increment = 1,
        Suffix = "%",
        Callback = function(value)
                print("[LiquidGlass] Intensity:", value)
        end,
})

General:CreateDropdown({
        Name = "Select Mode",
        Options = { "Performance", "Balanced", "Quality" },
        Default = "Balanced",
        Callback = function(option)
                print("[LiquidGlass] Mode:", option)
        end,
})

General:CreateSection({ Name = "Reset" })

General:CreateButton({
        Name = "Reset Intensity to 50",
        Callback = function()
                intensity:Set(50)
                Window:Notify({ Title = "Intensity", Description = "Reset to 50%.", Type = "info", Duration = 2 })
        end,
})

--==========================================================================================
-- TAB: INPUT
--==========================================================================================
local InputTab = Window:CreateTab({ Name = "Input", Icon = "✎" })

InputTab:CreateSection({ Name = "Text" })

InputTab:CreateTextInput({
        Name = "Nickname",
        Placeholder = "Type your name…",
        Callback = function(text, enterPressed)
                print("[LiquidGlass] Nickname:", text, enterPressed)
        end,
})

InputTab:CreateSearchField({
        Name = "Search",
        Callback = function(text)
                print("[LiquidGlass] Search:", text)
        end,
})

InputTab:CreateSection({ Name = "Advanced input" })

InputTab:CreateKeybind({
        Name = "Toggle Fly",
        Default = Enum.KeyCode.F,
        Callback = function()
                print("[LiquidGlass] Fly toggled!")
        end,
})

InputTab:CreateColorPicker({
        Name = "Accent Color",
        Default = Color3.fromRGB(92, 158, 255),
        Callback = function(color)
                Window:SetAccent(color)
                print("[LiquidGlass] Accent:", color)
        end,
})

InputTab:CreateDropdown({
        Name = "Multi Select",
        Multi = true,
        Options = { "ESP", "Aimbot", "Speed", "Fly", "Noclip" },
        Callback = function(selected)
                print("[LiquidGlass] Multi:", selected)
        end,
})

--==========================================================================================
-- TAB: VISUALS
--==========================================================================================
local Visuals = Window:CreateTab({ Name = "Visuals", Icon = "◐" })

Visuals:CreateSection({ Name = "Indicators" })

local progress = Visuals:CreateProgress({
        Name = "Download",
        Default = 0,
})

local ring = Visuals:CreateProgressRing({
        Name = "Battery",
        Default = 72,
})

Visuals:CreateBadge({
        Text = "ONLINE",
        Variant = "Success",
})

Visuals:CreateSection({ Name = "Progress actions" })

Visuals:CreateButton({
        Name = "Animate progress",
        Callback = function()
                task.spawn(function()
                        for v = 0, 100, 4 do
                                progress:Set(v)
                                task.wait(0.03)
                        end
                        Window:Notify({ Title = "Download", Description = "Complete.", Type = "success", Duration = 3 })
                end)
        end,
})

Visuals:CreateButton({
        Name = "Pulse (indeterminate)",
        Callback = function()
                progress:Pulse()
        end,
})

Visuals:CreateSection({ Name = "Theme engine" })

Visuals:CreateDropdown({
        Name = "Theme",
        Options = LiquidGlass:GetThemeNames(),
        Default = "Midnight",
        Callback = function(name)
                Window:SetTheme(name)
                Window:Notify({ Title = "Theme", Description = "Switched to " .. name, Type = "info", Duration = 2 })
        end,
})

--==========================================================================================
-- TAB: ADVANCED
--==========================================================================================
local AdvancedTab = Window:CreateTab({ Name = "Advanced", Icon = "✦" })

AdvancedTab:CreateSection({ Name = "Overlays" })

AdvancedTab:CreateButton({
        Name = "Confirmation dialog",
        Callback = function()
                Window:Dialog({
                        Title = "Delete save data?",
                        Content = "This action cannot be undone. Your settings will be reset to defaults.",
                        Icon = "alert",
                        Buttons = {
                                { Text = "Cancel" },
                                { Text = "Delete", Primary = true, Callback = function()
                                        Window:Notify({ Title = "Deleted", Description = "Save data cleared.", Type = "danger", Duration = 3 })
                                end },
                        },
                })
        end,
})

AdvancedTab:CreateButton({
        Name = "Show loading overlay",
        Callback = function()
                local loading = Window:Loading()
                loading:Show("Preparing assets…")
                task.delay(1.8, function()
                        loading:Hide()
                        Window:Notify({ Title = "Ready", Description = "Assets loaded.", Type = "success", Duration = 2 })
                end)
        end,
})

AdvancedTab:CreateButton({
        Name = "Open command palette (Ctrl+K)",
        Callback = function()
                if Window._palette then
                        Window._palette:Open()
                end
        end,
})

AdvancedTab:CreateSection({ Name = "Floating widgets" })

AdvancedTab:CreateButton({
        Name = "Toggle dock",
        Callback = function()
                if Window._demoDock then
                        Window._demoDock:Destroy()
                        Window._demoDock = nil
                else
                        Window._demoDock = Window:CreateDock({
                                Items = {
                                        { Name = "Home", Icon = "⌂", Callback = function() Window:SelectTab(1) end },
                                        { Name = "Visuals", Icon = "◐", Callback = function() Window:SelectTab(3) end },
                                        { Name = "Notify", Icon = "✦", Callback = function()
                                                Window:Notify({ Title = "Dock", Description = "Hello from the dock!", Type = "info", Duration = 2 })
                                        end },
                                        { Name = "Close", Icon = "✕", Callback = function() Window:Hide() end },
                                },
                        })
                end
        end,
})

AdvancedTab:CreateButton({
        Name = "Toggle radial menu",
        Callback = function()
                if Window._demoRadial then
                        Window._demoRadial:Destroy()
                        Window._demoRadial = nil
                else
                        Window._demoRadial = Window:CreateRadialMenu({
                                Radius = 86,
                                Items = {
                                        { Name = "General", Icon = "⌂", Callback = function() Window:SelectTab(1) end },
                                        { Name = "Input", Icon = "✎", Callback = function() Window:SelectTab(2) end },
                                        { Name = "Visuals", Icon = "◐", Callback = function() Window:SelectTab(3) end },
                                        { Name = "Notify", Icon = "✦", Callback = function()
                                                Window:Notify({ Title = "Radial", Description = "Radial menu works.", Type = "success", Duration = 2 })
                                        end },
                                },
                        })
                        Window._demoRadial:Open()
                end
        end,
})

AdvancedTab:CreateButton({
        Name = "Spawn floating action button",
        Callback = function()
                if Window._demoFAB then
                        Window._demoFAB:Destroy()
                        Window._demoFAB = nil
                else
                        Window._demoFAB = Window:CreateFAB({
                                Icon = "✦",
                                Callback = function()
                                        if Window._demoRadial then
                                                Window._demoRadial.Open()
                                        end
                                end,
                        })
                end
        end,
})

-- right-click anywhere on the window for a context menu
Window:CreateContextMenu(Window._root, {
        Items = {
                { Name = "Maximize / restore", Callback = function() Window:ToggleMaximize() end },
                { Name = "Minimize", Callback = function() Window:Minimize() end },
                { Name = "Toggle compact sidebar", Callback = function() Window:SetCompact(not Window._compact) end },
                { Divider = true },
                { Name = "Reload UI", Callback = function()
                        Window:Hide()
                        task.delay(0.4, function() Window:Show() end)
                end },
        },
})

--==========================================================================================
-- TAB: SETTINGS
--==========================================================================================
local Settings = Window:CreateTab({ Name = "Settings", Icon = "⚙" })

Settings:CreateSection({ Name = "Performance" })

Settings:CreateDropdown({
        Name = "Quality",
        Options = { "High", "Balanced", "Low" },
        Default = LiquidGlass.Config.Quality,
        Callback = function(option)
                LiquidGlass:SetQuality(option)
                Window:Notify({ Title = "Quality", Description = option, Type = "info", Duration = 2 })
        end,
})

Settings:CreateToggle({
        Name = "Reduced Motion",
        Description = "Accessibility: disables every animation",
        Default = LiquidGlass.Config.ReducedMotion,
        Callback = function(value)
                LiquidGlass:SetReducedMotion(value)
        end,
})

Settings:CreateToggle({
        Name = "Drag Momentum",
        Default = LiquidGlass.Config.DragMomentum,
        Callback = function(value)
                LiquidGlass:Configure({ DragMomentum = value })
        end,
})

Settings:CreateSection({ Name = "Window" })

Settings:CreateDropdown({
        Name = "Sidebar Mode",
        Options = { "Full", "Compact" },
        Default = Window._compact and "Compact" or "Full",
        Callback = function(option)
                Window:SetCompact(option == "Compact")
        end,
})

Settings:CreateSlider({
        Name = "Animation Speed",
        Min = 0.25,
        Max = 2,
        Default = 1,
        Increment = 0.25,
        Suffix = "x",
        Callback = function(value)
                LiquidGlass:Configure({ Animation = { Speed = value } })
        end,
})

Settings:CreateSection({ Name = "Danger zone" })

Settings:CreateButton({
        Name = "Unload LiquidGlass",
        Description = "Destroys every window and frees all connections",
        Callback = function()
                Window:Dialog({
                        Title = "Unload UI?",
                        Content = "All LiquidGlass windows will be destroyed and every connection cleaned up.",
                        Icon = "cross",
                        Buttons = {
                                { Text = "Stay" },
                                { Text = "Unload", Primary = true, Callback = function()
                                        LiquidGlass:DestroyAll()
                                end },
                        },
                })
        end,
})

--==========================================================================================
-- GREETING
--==========================================================================================
task.delay(0.8, function()
        Window:Notify({
                Title = "LiquidGlass",
                Description = "Everything is running smoothly.",
                Type = "success",
                Duration = 4,
        })
end)
