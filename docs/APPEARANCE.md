# Appearance System

Iguana's visual style is organized into **skins** — self-contained folders that bundle a theme, style, and icon pack together. Select a complete skin in Settings to apply everything at once, or mix and match individual components for a custom look.

```
ui/appearance/
├── aero/              ← complete skin folder
│   ├── theme.tres     ← color palette (UITheme)
│   ├── style.tres     ← shader params + animation (UIStyle)
│   ├── style.gdshader ← optional custom UI overlay shader
│   ├── Geist.ttf      ← optional custom font (first .ttf/.otf found)
│   └── icons/         ← SVG icon set
├── iguana/
└── kitty/
```

---

## Creating a New Skin

1. Duplicate an existing skin folder (e.g. `ui/appearance/aero/`) and rename it.
2. Edit `theme.tres` colors in the Godot Inspector.
3. Optionally edit `style.tres` shader parameters and animation timing.
4. Optionally add a custom `style.gdshader` and update `shader_path` in `style.tres`.
5. Optionally drop a `.ttf` or `.otf` font file into the folder for a custom typeface.
6. Replace the SVGs in `icons/` with your own designs.
7. It appears in Settings → Appearance → Skin automatically.

If you only want to change colors, you only need to edit `theme.tres`.

---

## Themes — Color Palettes

A theme is a `UITheme` resource. It controls every color used to build UI panels, buttons, sliders, borders, and separators.

**To edit a theme:** open the skin's `theme.tres` in the Godot Inspector and adjust the exported color properties.

**Glass panel colors:**

| Property | Purpose |
|---|---|
| `c_glass` | Main panel background |
| `c_glass_lt` | Lighter panel variant |
| `c_glass_dark` | Darker panel variant (player bar) |
| `c_logo` | Logo pill background |

**Border & shadow colors:**

| Property | Purpose |
|---|---|
| `c_border` | Subtle border on inactive elements |
| `c_hilite` | Bright border on active / hovered elements |
| `c_shadow` | Drop shadow color |

**Button colors:**

| Property | Purpose |
|---|---|
| `c_btn` | Button normal background |
| `c_btn_h` | Button hover background |
| `c_btn_p` | Button pressed background |
| `c_accent` | Active tab / accent highlight |

**Slider colors:**

| Property | Purpose |
|---|---|
| `c_slider_bg` | Slider track background |
| `c_slider_fill` | Slider fill (left of thumb) |
| `c_grabber` | Slider thumb normal |
| `c_grabber_h` | Slider thumb hovered |

**Panel colors:**

| Property | Purpose |
|---|---|
| `c_title_bar` | Window title bar background |
| `c_panel_bg` | Content panel background |
| `c_footer_bar` | Footer bar background |
| `c_active_row` | Active / selected playlist row |
| `c_zebra` | Alternating row stripe (keymap tab) |

**Tab colors:**

| Property | Purpose |
|---|---|
| `c_tab_fg` | Active tab background |
| `c_tab_bg` | Inactive tab background |
| `c_tab_hover` | Hovered tab background |

**Dropdown colors:**

| Property | Purpose |
|---|---|
| `c_drop_bg` | Popup list panel background |
| `c_drop_border` | Popup list border |
| `c_drop_hover` | Hovered item highlight |
| `c_drop_pressed` | Pressed / selected item background |

**Separator & text colors:**

| Property | Purpose |
|---|---|
| `c_sep` | Separator base (invisible container) |
| `c_sep_draw` | Separator drawn line / caps |
| `c_link` | Hyperlink label normal |
| `c_link_h` | Hyperlink label hovered |
| `c_section` | Section header label |
| `c_text_hi` | Highlighted text color |
| `c_text_dim` | Dimmed / secondary text color |

**Notification properties:**

| Property | Default | Purpose |
|---|---|---|
| `c_notify_shadow` | Color(0,0,0,0.6) | Notification text shadow color |
| `notify_offset` | Vector2(16, 14) | Notification position on screen |

**Font size properties:**

| Property | Default | Purpose |
|---|---|---|
| `font_notification` | 22 | Notification overlay label |
| `font_title` | 14 | Window title bars, about name, keymap rows |
| `font_body` | 12 | Body text, labels, playlist rows |
| `font_section` | 10 | Section header labels |
| `font_version` | 11 | Version stamp in About tab |

**Text opacity properties:**

| Property | Default | Purpose |
|---|---|---|
| `a_time_label` | 0.70 | Time display in player bar |
| `a_footer_stats` | 0.60 | Playlist footer track count |
| `a_info_text` | 0.75 | Info / description text |
| `a_label_text` | 0.55 | Row labels in About tab |
| `a_tagline` | 0.65 | Tagline text |
| `a_version` | 0.35 | Version stamp |
| `a_empty_msg` | 0.45 | Empty state messages |
| `a_track_num` | 0.40 | Track number labels |
| `a_duration` | 0.50 | Track duration labels |
| `a_dim_icon` | 0.50 | Dimmed icons (shuffle inactive, remove btn) |

**Debug colors:**

| Property | Purpose |
|---|---|
| `c_dbg_bg` | Debug bar background |
| `c_dbg_fill` | Debug bar fill |

---

## Fonts

Each skin can optionally include a custom typeface. Drop a single `.ttf` or `.otf` file into the skin folder alongside `theme.tres`. The first font file found is loaded and applied to all UI labels, buttons, tabs, and built-in controls.

**If no font file is present**, the engine default (Inter) is used — no configuration needed.

```
ui/appearance/aero/
├── theme.tres
├── style.tres
├── Geist.ttf          ← optional: any .ttf or .otf
└── icons/
```

**Guidelines for skin fonts:**

- Use a single weight (Regular 400 works best at the default font sizes).
- Prefer fonts with good legibility at 10–14px — the UI is compact.
- Any SIL Open Font License or public domain font can be bundled.
- Only the first `.ttf` / `.otf` file alphabetically is loaded; extras are ignored.

**How it works internally:**

| Method | What it covers |
|---|---|
| `StylesUI.apply_font(lbl)` | Apply font to a single label (used for dynamically created playlist rows) |
| `StylesUI.track_label()` | Tracks a label and applies font + re-applies on skin switch |
| `Theme.default_font` | Set on the settings window `Theme` — covers CheckBox, OptionButton, TabBar, etc. |

---

## Styles — UI Shader + Parameters

A style is a `UIStyle` resource. It points at a `.gdshader` file and carries two full sets of shader uniform values: one for *subtle* mode (settings panels, playlist) and one for *normal* mode (the player bar). It also controls animation parameters and logo placement.

**To create a new style:**

1. Write or copy a `canvas_item` shader as `style.gdshader` inside your skin folder.
2. Duplicate an existing `style.tres` from another skin and place it in your skin folder.
3. Set `shader_path` to `"res://ui/appearance/<your_skin>/style.gdshader"`.
4. Tune the exported parameters.
5. The skin appears in Settings → Appearance → Skin automatically.

**Logo properties:**

| Property | Default | Purpose |
|---|---|---|
| `logo_visible` | `true` | Show / hide the logo pill on the player bar |
| `logo_anchor` | 0 (Center) | Logo position: 0 = Center, 1 = Left, 2 = Right |

**Animation properties:**

| Property | Default | Purpose |
|---|---|---|
| `anim_autohide_duration` | 0.35 | Player bar auto-hide slide duration (seconds) |
| `anim_autohide_trans` | 7 (Cubic) | Auto-hide easing transition type |
| `anim_win_open_duration` | 0.30 | Window open slide duration |
| `anim_win_open_ease` | 1 (Out) | Window open easing direction |
| `anim_win_open_trans` | 7 (Cubic) | Window open transition type |
| `anim_win_close_duration` | 0.22 | Window close slide duration |
| `anim_win_close_ease` | 0 (In) | Window close easing direction |
| `anim_win_close_trans` | 7 (Cubic) | Window close transition type |
| `anim_win_fade_in` | 0.22 | Window content fade-in duration |
| `anim_win_fade_out` | 0.18 | Window content fade-out duration |
| `anim_crossfade_out` | 0.20 | Track label crossfade-out duration |
| `anim_crossfade_in` | 0.30 | Track label crossfade-in duration |

Transition enum indices: 0 = Linear, 1 = Sine, 2 = Quint, 3 = Quart, 4 = Quad, 5 = Expo, 6 = Elastic, 7 = Cubic, 8 = Circ, 9 = Bounce, 10 = Back, 11 = Spring.

Ease enum indices: 0 = In, 1 = Out, 2 = In Out, 3 = Out In.

**Subtle / Normal shader properties:**

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

Each skin has its own `icons/` subfolder containing SVG files. Replace them to customize the look.

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

All changes apply instantly when changed in Settings. No restart required.

The reload system works by tracking every styled control in weak-reference arrays inside `StylesUI`. When a new skin is selected or individual components are changed:

1. `StylesUI.load_skin()` (or `load_theme/style/icons()` for overrides) swaps the active resource(s).
2. `StylesUI.reload_all()` iterates every tracked control and re-applies styles in place — shader uniforms are updated, `StyleBoxFlat` objects are recreated, icons are re-loaded from the new pack.

**Automatic tracking:**

| Method | Tracks |
|---|---|
| `apply_bar_style()` | Player bar panel |
| `apply_glass_btn()` | All icon/text buttons |
| `apply_glass_slider()` | All sliders |
| `apply_aero()` | All shader panels (material uniforms) |
| `apply_dropdown()` | All OptionButton dropdowns + popup lists |
| `make_vsep()` / `win_sep()` | All separators |
| `icon_btn()` | All icon buttons |
| `track_glass_panel()` | Window chrome (title bars, content panels, footers, logo, tabs) |
| `track_label()` | Labels with theme-driven font size / color / font |
| `apply_font()` | Apply the active skin font to any label (used for dynamic labels like playlist rows) |

**Manual reload:** Components can register callbacks with `StylesUI.on_reload(callable)` for parts that cannot be automatically tracked (e.g. playlist row regeneration).
