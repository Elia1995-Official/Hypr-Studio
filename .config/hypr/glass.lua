-- HyprGlass (liquid glass: refraction, chromatic edge, specular). Built from ~/.local/share/hyprglass/src
-- (branch hyprland-0.56, needs CPLUS_INCLUDE_PATH=~/.local/share/hyprglass/inc because /usr/local/include/hyprland is stale).
-- hl.plugin.load() from Lua is a no-op on this setup, so autostart.lua loads the .so with hyprctl and reloads once.
-- Whitelist mode: only windows tagged hyprglass_enabled (kitty) get glass; bar/launcher keep the normal blur.
local hg = hl.plugin.hyprglass
if hg then
    hg.config({
        enabled = false,
        default_theme = "dark",
        default_preset = "kitty",
    })
    -- Apple-style Liquid Glass: clear pane, thin curved lens edge that bends/mirrors the backdrop,
    -- bright specular rim on the focused window, frosting only where it passes over other windows.
    hg.preset("kitty", {
        inherits = "pomme",
        blur_strength = 1.0,
        blur_iterations = 2,
        refraction_strength = 2.0,
        refraction_flow = 1.0,
        chromatic_aberration = 0.0,
        fresnel_strength = 0.1,
        specular_strength = 0.4,
        bevel_strength = 0.5,
        bevel_size = 4.0,
        bevel_tint = 0.5,
        bevel_angle = 315.0,
        edge_thickness = 0.024,
        edge_thickness_px = 0.0,
        edge_height = 0.0,
        fresnel_reflection = 0.05,
        frost = 0.0,
        focus_light = 0.0,
        lens_distortion = 0.503,
        noise_strength = 0.0,
        tint_color = 0x1a1a1a4a,
        brightness = 1.1,
        contrast = 0.9,
        saturation = 1.0,
        vibrancy = 0.0,
    })
end

hl.window_rule({ name = "kitty-hyprglass", match = { class = "^(kitty)$" }, tag = "+hyprglass_enabled" })
