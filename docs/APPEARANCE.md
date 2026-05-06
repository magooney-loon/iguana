# Appearance System

Iguana's visual style is split across four independent axes. Each can be swapped live in Settings without restarting the engine. Mix and match freely — a "dracula" theme works with the "aero" skin and any icon pack.

```
ui/appearance/
├── themes/    ← color palettes        (.tres → UITheme)
├── skins/     ← shape / radius sets   (.tres → UISkin)
├── styles/    ← UI shader + params    (.tres → UIStyle)
└── icons/     ← icon packs            (one subfolder per pack)
```

---

## Themes — Color Palettes

A theme is a `UITheme` resource. It controls every color used to build UI panels, buttons, sliders, borders, and separators.

**To create a new theme:**

1. Duplicate `ui/appearance/themes/aero_blue.tres` and rename it (e.g. `dracula.tres`).
2. Open it in the Godot editor Inspector and adjust the exported color properties.
3. Drop it into `ui/appearance/themes/`. It will appear in the Settings → Appearance → Theme dropdown automatically.

**Color properties:**

| Property | Purpose |
|---|---|
| `c_glass` | Main panel background |
| `c_glass_lt` | Lighter panel variant |
| `c_glass_dark` | Darker panel variant (player bar) |
| `c_logo` | Logo pill background |
| `c_border` | Subtle border on inactive elements |
| `c_hilite` | Bright border on active / hovered elements |
| `c_shadow` | Drop shadow color |
| `c_btn` | Button normal background |
| `c_btn_h` | Button hover background |
| `c_btn_p` | Button pressed background |
| `c_accent` | Active tab / accent highlight |
| `c_slider_bg` | Slider track background |
| `c_slider_fill` | Slider fill (left of thumb) |
| `c_grabber` | Slider thumb normal |
| `c_grabber_h` | Slider thumb hovered |
| `c_sep` | Separator base (invisible container) |
| `c_sep_draw` | Separator drawn line / caps |
| `c_link` | Hyperlink label normal |
| `c_link_h` | Hyperlink label hovered |
| `c_section` | Section header label |

---

## Skins — Shape & Radius Sets

A skin is a `UISkin` resource. It controls corner radii, padding, and the animated separator parameters — the *shape* of the UI, independent of color.

**To create a new skin:**

1. Duplicate `ui/appearance/skins/aero.tres` and rename it.
2. Adjust the exported float properties in the Inspector.
3. Drop it into `ui/appearance/skins/`. It appears in Settings → Appearance → Skin.

**Shape properties:**

| Property | Default | Purpose |
|---|---|---|
| `btn_radius` | 7.0 | Button corner radius (px) |
| `panel_radius` | 10.0 | Panel corner radius (px) |
| `bar_radius` | 12.0 | Player bar corner radius (px) |
| `logo_radius` | 18.0 | Logo pill corner radius (px) |
| `bar_shadow_size` | 16 | Player bar drop shadow size (px) |
| `bar_padding_h` | 14.0 | Player bar horizontal inner padding |
| `bar_padding_v` | 8.0 | Player bar vertical inner padding |
| `slider_track_compact` | 4.0 | Slider track height in compact mode |
| `slider_track_normal` | 6.0 | Slider track height in normal mode |
| `slider_grab_compact` | 12.0 | Slider thumb margin in compact mode |
| `slider_grab_normal` | 14.0 | Slider thumb margin in normal mode |
| `sep_base_wave` | 0.5 | Separator idle wave amplitude |
| `sep_base_cap` | 1.8 | Separator endpoint cap radius |

---

## Styles — UI Shader + Parameters

A style is a `UIStyle` resource. It points at a `.gdshader` file and carries two full sets of shader uniform values: one for *subtle* mode (settings panels, playlist) and one for *normal* mode (the player bar).

**To create a new style:**

1. Write or copy a `canvas_item` shader into `ui/appearance/styles/`. The shader must accept the uniforms listed in the *Shader Uniforms* section below.
2. Duplicate `ui/appearance/styles/aero_glass.tres` and rename it.
3. Set `shader_path` to point at your new shader file.
4. Tune the `subtle_*` and `normal_*` exported parameters.
5. Drop the `.tres` into `ui/appearance/styles/`. It appears in Settings → Appearance → Style.

**UIStyle exported parameters:**

| Group | Property | Purpose |
|---|---|---|
| General | `shader_path` | Path to the `.gdshader` file |
| Subtle mode | `subtle_grain_strength` | Film grain intensity |
| | `subtle_grain_speed` | Grain animation speed |
| | `subtle_vignette_strength` | Edge darkening amount |
| | `subtle_vignette_pulse` | Vignette breathe amplitude |
| | `subtle_vignette_pulse_spd` | Vignette breathe speed |
| | `subtle_specular_strength` | Gloss / specular highlight intensity |
| | `subtle_specular_y_pos` | Specular band vertical position |
| | `subtle_specular_height` | Specular band height |
| | `subtle_corner_radius` | SDF corner radius for specular glow |
| | `subtle_gradient_strength` | Top-to-bottom lighting gradient |
| | `subtle_fresnel_strength` | Fresnel edge bloom intensity |
| | `subtle_fresnel_width` | Fresnel edge width |
| | `subtle_bevel_strength` | Bevel highlight/shadow intensity |
| | `subtle_bevel_width` | Bevel width |
| | `subtle_gloss_texture_str` | Micro-texture grain strength |
| | `subtle_caustic_scale` | Caustic ripple frequency |
| | `subtle_iridescence` | Iridescent color shift amount |
| Normal mode | `normal_*` | Same properties, used for the player bar |

**Required shader uniforms** (the engine sets these automatically):

```glsl
uniform float grain_strength;
uniform float grain_speed;
uniform float vignette_strength;
uniform float vignette_pulse;
uniform float vignette_pulse_spd;
uniform float specular_strength;
uniform float specular_y_pos;
uniform float specular_height;
uniform float corner_radius;
uniform float gradient_strength;
uniform float fresnel_strength;
uniform float fresnel_width;
uniform float bevel_strength;
uniform float bevel_width;
uniform float gloss_texture_str;
uniform float caustic_scale;
uniform float iridescence;

// Audio-reactive (set each frame by StylesUI.update_audio)
uniform float beat;
uniform float energy;
uniform float bass;

// Per-panel randomized seed (set once on panel creation)
uniform float wave_seed;
```

---

## Icon Packs

Icon packs are plain folders — no `.tres` file needed. Drop a folder into `ui/appearance/icons/` and it appears in Settings → Appearance → Icons.

**Required icons** (one `.svg` per name, any resolution):

```
add.svg         clear.svg       close.svg
fullscreen.svg  loop_all.svg    loop_none.svg
loop_one.svg    next.svg        pause.svg
play.svg        playlist.svg    prev.svg
remove.svg      reset.svg       save.svg
settings.svg    shuffle.svg     stop.svg
volume_high.svg volume_low.svg  volume_muted.svg
```

Missing icons fall back to an empty texture with a console warning, so you can ship a partial pack if you only want to replace specific icons.

---

## Live Reload

All four axes apply instantly when changed in Settings. No restart required.

The reload system works by tracking every styled control in weak-reference arrays inside `StylesUI`. When a new theme/skin/style/icons is selected:

1. `StylesUI.load_theme/skin/style/icons()` swaps the active resource.
2. `StylesUI.reload_all()` iterates every tracked control and re-applies styles in place — shader uniforms are updated, `StyleBoxFlat` objects are recreated, icons are re-loaded from the new pack.

Components can register callbacks with `StylesUI.on_reload(callable)` for parts that cannot be automatically tracked (e.g. `TabContainer` tab styles, playlist row regeneration).
