--@module LiquidGlass/Core/Themes
--[[
        LiquidGlass · Core/Themes
        Adaptive theme system. Each theme is a flat table of Color3 values.
        Register custom themes with LiquidGlass:RegisterTheme(name, table) —
        any key you omit is inherited from Midnight.
]]

local Themes = {}

local function rgb(r, g, b)
        return Color3.fromRGB(r, g, b)
end

local function copy(t)
        local out = {}
        for k, v in pairs(t) do
                out[k] = v
        end
        return out
end

--====================================================================================
-- BUILT-IN THEMES
--====================================================================================

Themes.List = {
        Midnight = {
                Name = "Midnight",
                Dark = true,
                Background = rgb(13, 15, 22),
                Surface = rgb(21, 24, 34),
                SurfaceHigh = rgb(29, 34, 47),
                Stroke = rgb(76, 84, 108),
                InnerStroke = rgb(47, 53, 69),
                Divider = rgb(34, 39, 52),
                TextPrimary = rgb(237, 241, 249),
                TextSecondary = rgb(151, 160, 180),
                TextMuted = rgb(105, 113, 134),
                Accent = rgb(92, 158, 255),
                Accent2 = rgb(148, 122, 255),
                OnAccent = rgb(10, 16, 28),
                Success = rgb(74, 205, 148),
                Danger = rgb(255, 96, 114),
                Warning = rgb(255, 193, 94),
                Track = rgb(15, 17, 25),
                Knob = rgb(242, 245, 252),
                Shadow = rgb(0, 0, 0),
                Highlight = rgb(255, 255, 255),
                HighlightT = 0.93,
                ShadeTop = rgb(255, 255, 255),
                ShadeBottom = rgb(168, 176, 198),
                Scroller = rgb(92, 158, 255),
                Overlay = rgb(6, 8, 12),
        },

        Arctic = {
                Name = "Arctic",
                Dark = false,
                Background = rgb(233, 237, 244),
                Surface = rgb(247, 249, 252),
                SurfaceHigh = rgb(255, 255, 255),
                Stroke = rgb(186, 195, 211),
                InnerStroke = rgb(214, 221, 232),
                Divider = rgb(222, 228, 238),
                TextPrimary = rgb(27, 33, 46),
                TextSecondary = rgb(104, 114, 133),
                TextMuted = rgb(151, 159, 173),
                Accent = rgb(0, 120, 255),
                Accent2 = rgb(96, 84, 255),
                OnAccent = rgb(255, 255, 255),
                Success = rgb(28, 168, 108),
                Danger = rgb(228, 74, 86),
                Warning = rgb(224, 146, 32),
                Track = rgb(222, 227, 236),
                Knob = rgb(255, 255, 255),
                Shadow = rgb(70, 80, 105),
                Highlight = rgb(255, 255, 255),
                HighlightT = 0.55,
                ShadeTop = rgb(255, 255, 255),
                ShadeBottom = rgb(219, 225, 236),
                Scroller = rgb(0, 120, 255),
                Overlay = rgb(20, 26, 38),
        },

        Aurora = {
                Name = "Aurora",
                Dark = true,
                Background = rgb(9, 14, 19),
                Surface = rgb(15, 22, 30),
                SurfaceHigh = rgb(22, 32, 42),
                Stroke = rgb(62, 110, 112),
                InnerStroke = rgb(40, 66, 70),
                Divider = rgb(28, 44, 50),
                TextPrimary = rgb(232, 248, 246),
                TextSecondary = rgb(136, 170, 170),
                TextMuted = rgb(96, 124, 128),
                Accent = rgb(52, 224, 196),
                Accent2 = rgb(122, 138, 255),
                OnAccent = rgb(6, 22, 20),
                Success = rgb(84, 220, 160),
                Danger = rgb(255, 96, 114),
                Warning = rgb(255, 200, 90),
                Track = rgb(10, 16, 22),
                Knob = rgb(240, 252, 250),
                Shadow = rgb(0, 0, 0),
                Highlight = rgb(255, 255, 255),
                HighlightT = 0.93,
                ShadeTop = rgb(255, 255, 255),
                ShadeBottom = rgb(150, 186, 190),
                Scroller = rgb(52, 224, 196),
                Overlay = rgb(4, 8, 11),
        },

        Sunset = {
                Name = "Sunset",
                Dark = true,
                Background = rgb(24, 14, 17),
                Surface = rgb(35, 21, 26),
                SurfaceHigh = rgb(46, 29, 35),
                Stroke = rgb(118, 74, 78),
                InnerStroke = rgb(74, 48, 54),
                Divider = rgb(54, 36, 42),
                TextPrimary = rgb(255, 240, 236),
                TextSecondary = rgb(208, 166, 160),
                TextMuted = rgb(152, 114, 112),
                Accent = rgb(255, 118, 92),
                Accent2 = rgb(255, 176, 84),
                OnAccent = rgb(42, 14, 10),
                Success = rgb(120, 200, 140),
                Danger = rgb(255, 96, 114),
                Warning = rgb(255, 190, 94),
                Track = rgb(18, 11, 14),
                Knob = rgb(255, 244, 240),
                Shadow = rgb(0, 0, 0),
                Highlight = rgb(255, 255, 255),
                HighlightT = 0.93,
                ShadeTop = rgb(255, 255, 255),
                ShadeBottom = rgb(190, 148, 148),
                Scroller = rgb(255, 118, 92),
                Overlay = rgb(12, 6, 8),
        },

        Obsidian = {
                Name = "Obsidian",
                Dark = true,
                Background = rgb(10, 10, 12),
                Surface = rgb(18, 18, 21),
                SurfaceHigh = rgb(27, 27, 31),
                Stroke = rgb(72, 72, 82),
                InnerStroke = rgb(46, 46, 52),
                Divider = rgb(37, 37, 43),
                TextPrimary = rgb(240, 240, 244),
                TextSecondary = rgb(154, 154, 164),
                TextMuted = rgb(110, 110, 121),
                Accent = rgb(235, 235, 242),
                Accent2 = rgb(150, 150, 162),
                OnAccent = rgb(15, 15, 18),
                Success = rgb(120, 220, 150),
                Danger = rgb(255, 96, 110),
                Warning = rgb(240, 190, 100),
                Track = rgb(13, 13, 16),
                Knob = rgb(255, 255, 255),
                Shadow = rgb(0, 0, 0),
                Highlight = rgb(255, 255, 255),
                HighlightT = 0.94,
                ShadeTop = rgb(255, 255, 255),
                ShadeBottom = rgb(146, 146, 156),
                Scroller = rgb(200, 200, 210),
                Overlay = rgb(5, 5, 6),
        },
}

--====================================================================================
-- API
--====================================================================================

function Themes.Register(name, overrides)
        local base = copy(Themes.List.Midnight)
        base.Name = name
        if overrides then
                for key, value in pairs(overrides) do
                        base[key] = value
                end
        end
        Themes.List[name] = base
        return base
end

function Themes.Get(name)
        return Themes.List[name] or Themes.List.Midnight
end

function Themes.Names()
        local names = {}
        for name in pairs(Themes.List) do
                table.insert(names, name)
        end
        table.sort(names)
        return names
end

-- Resolve a theme spec: nil | string | table ---------------------------------------
function Themes.Resolve(spec)
        if type(spec) == "string" then
                return copy(Themes.Get(spec))
        elseif type(spec) == "table" then
                local base = copy(Themes.List.Midnight)
                for key, value in pairs(spec) do
                        base[key] = value
                end
                if base.Name == "Midnight" then
                        base.Name = "Custom"
                end
                return base
        end
        return copy(Themes.List.Midnight)
end

return Themes
