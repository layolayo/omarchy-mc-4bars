# Omarchy MC 4Bars (`io.github.layolayo.mc-4bars`)

A native Quad-Edge Status Bar plugin for **Omarchy / Quickshell** (`omarchy-shell`) that extends Omarchy's primary status bar (`config.bar`) with up to **three additional independent status bars** (`bottomBar`, `leftBar`, `rightBar`) across all four screen edges (`top`, `bottom`, `left`, `right`).

---

## Key Features

- **Quad-Edge Status Bar Architecture (`top`, `bottom`, `left`, `right`)**:
  - Hosts any installed Omarchy bar widget across `bar` (Primary), `bottomBar` (Secondary 1), `leftBar` (Secondary 2), and `rightBar` (Secondary 3), each with its own **Left (`L`)**, **Middle / Centre (`M`)**, and **Right (`R`)** sections.
- **Lazy Instantiation + Warm Off-Screen Parking**:
  - **Empty Bars (`0` widgets)**: Remain completely **dormant** (`Variants { model: [] }`) and allocate **zero** Wayland `wlr-layer-shell` surfaces or GPU buffers until you move at least one widget onto them.
  - **Populated Bars (`≥ 1` widget)**: Use upstream Omarchy's **warm off-screen parking** (`ExclusionMode.Ignore`, negative edge margins, transparent background, and hidden inner loader) when toggled off or hidden by fullscreen windows, guaranteeing instantaneous (`~0 ms`) show/hide transitions without Wayland surface remap glitches.
- **Automatic Edge Swapping**:
  - Moving any bar onto a screen edge that is already occupied by another bar (by dragging the bar's empty space, clicking an edge in the Visual Layout Manager, or running `omarchy mc-4bars position` / `swap`) **automatically swaps** the two bars' edges in `~/.config/omarchy/shell.json`.
- **Automatic Fullscreen & Fullscreen-Desktop Hiding**:
  - Automatically hides secondary bars on any monitor where the active workspace enters native fullscreen (`SPACE + F`) or Omarchy fullscreen-desktop (`SUPER + F` / `window-no-gaps.lua`), and restores them as soon as you exit fullscreen or switch workspaces.
- **Visual 4-Bar Layout Manager (`ManagerPanel.qml`)**:
  - Built-in graphical overlay panel (`omarchy mc-4bars manager`) to inspect active/dormant bar status, move or reorder widgets across all 4 bars and `L`/`M`/`R` sections, swap screen edges, and switch background styles (`none`, `glassy`, `opaque`).

---

## Keyboard Shortcuts (Hyprland)

Configured in `~/.config/hypr/bindings.lua`:

| Keybinding | Action |
| :--- | :--- |
| **`SUPER + SPACE`** | Toggle the primary bar (`omarchy-toggle-bar`) |
| **`SHIFT + SUPER + ALT`** *(modifier chord)* | Toggle all populated secondary bars (`bottomBar`, `leftBar`, `rightBar`) |
| **`SUPER + SHIFT + ALT + SPACE`** | Toggle all populated secondary bars (explicit key fallback) |
| **`SUPER + CTRL + ALT + UP`** | Toggle whichever bar is currently on the **top** edge |
| **`SUPER + CTRL + ALT + DOWN`** | Toggle whichever bar is currently on the **bottom** edge |
| **`SUPER + CTRL + ALT + LEFT`** | Toggle whichever bar is currently on the **left** edge |
| **`SUPER + CTRL + ALT + RIGHT`** | Toggle whichever bar is currently on the **right** edge |

---

## Visual Layout Manager (`ManagerPanel.qml`)

Open the interactive Quad-Edge Layout Manager from your terminal:

```bash
omarchy mc-4bars manager
```

Or click the **MC 4Bars** (`󰕮`) icon if you add `"io.github.layolayo.mc-4bars"` to a bar layout.

Inside the Visual Layout Manager you can:
1. Switch between **Secondary 1 (`bottomBar`)**, **Secondary 2 (`leftBar`)**, **Secondary 3 (`rightBar`)**, and **Primary Bar (`bar`)** tabs (each tab displays its current screen edge and whether it is `active` or `dormant`).
2. Click **`top`**, **`bottom`**, **`left`**, or **`right`** under **Edge (Auto-Swaps)** to move the selected bar to that edge and automatically swap with any bar already on that edge.
3. Click **`none`**, **`glassy`**, or **`opaque`** to change the selected bar's background style.
4. Click **`L`**, **`M`**, or **`R`** on any widget card to move it between sections on the current bar, **`↑`** / **`↓`** to reorder it within a section, or **`→Top`** / **`→Bot`** / **`→Left`** / **`→Right`** to send it directly to another bar.

---

## Command-Line Interface (`CLI`) Reference

The CLI is installed at `~/.local/bin/omarchy-mc-4bars` (with backward-compatible aliases `omarchy mc-4bars`, `omarchy bottom-bar`, and `omarchy-bottom-bar`).

### 1. Inspect Bar Status & Layouts

```bash
omarchy mc-4bars
# or
omarchy mc-4bars list
```

Displays all 4 bar slots (`bar`, `bottomBar`, `leftBar`, `rightBar`), their assigned screen edge, background mode, active/dormant status, and widgets in `L (left)`, `M (center)`, and `R (right)`.

---

### 2. Move Widgets Between Any of the 4 Bars (`top`, `bottom`, `left`, `right`)

Move a widget to a specific edge bar (`top`, `bottom`, `left`, `right`) and section (`L`, `M`, `R`):

```bash
# Move 'voxtype' to the bottom bar's Middle/Centre (M) section:
omarchy mc-4bars bottom voxtype M

# Move 'weather' to the left vertical bar's Top/Left (L) section:
omarchy mc-4bars left weather L

# Move 'cpu' to the right vertical bar's Bottom/Right (R) section:
omarchy mc-4bars right cpu R

# Return 'voxtype' to the top bar's Right (R) section:
omarchy mc-4bars top voxtype R
```

You can also use `move <plugin-id> [edge-or-slot] <L|M|R>` with ordering flags (`--before <id>`, `--after <id>`, `--index <n>`):

```bash
omarchy mc-4bars move voxtype bottom M
omarchy mc-4bars move tailscale left L --index 0
omarchy mc-4bars move bluetooth top R --before audio
```

*(Note: When a widget is moved to any bar, the CLI automatically removes it from whichever bar previously held it so it is never duplicated).*

---

### 3. Swap Two Screen Edges (`swap` & `position`)

Swap the bars on any two screen edges (`top`, `bottom`, `left`, `right`):

```bash
# Swap the top bar and the bottom bar:
omarchy mc-4bars swap top bottom

# Swap the bottom bar and the left bar:
omarchy mc-4bars swap bottom left
```

Or assign a bar to a specific edge (automatically swapping with any bar already on that edge):

```bash
# Move bottomBar to 'left' (and swap leftBar to bottomBar's previous edge):
omarchy mc-4bars position left

# Move leftBar to 'top' (and swap the primary bar to leftBar's previous edge):
omarchy mc-4bars position top leftBar
```

You can also **drag any secondary bar's empty space** with the mouse to another edge of the screen to trigger an immediate live edge swap!

---

### 4. Show, Hide, or Toggle Bars (Global or Per-Edge)

```bash
# Toggle all populated secondary bars:
omarchy mc-4bars toggle

# Toggle only the bar on a specific screen edge:
omarchy mc-4bars toggle bottom
omarchy mc-4bars toggle left
omarchy mc-4bars toggle right
omarchy mc-4bars toggle top

# Explicitly show or hide all secondary bars (or a specific edge):
omarchy mc-4bars show [top|bottom|left|right]
omarchy mc-4bars hide [top|bottom|left|right]
```

---

### 5. Change Bar Background Style (`none`, `glassy`, `opaque`, `cycle`)

```bash
# Set background on bottomBar (default):
omarchy mc-4bars background glassy

# Set background on a specific edge or slot:
omarchy mc-4bars background opaque left
omarchy mc-4bars background cycle rightBar
```

---

### 6. Open a Widget's Panel or Remove a Widget

```bash
# Toggle a hosted plugin's popup/panel:
omarchy mc-4bars open voxtype

# Remove a widget from any secondary bar:
omarchy mc-4bars remove voxtype
```

---

## Direct Quickshell IPC Targets

`Bar.qml` registers the primary `ShellIpc` target `io.github.layolayo.mc-4bars` (plus backward-compatible aliases `io.github.layolayo.mc-2bars` and `matthew.bottom-bar`):

```bash
omarchy-shell io.github.layolayo.mc-4bars toggle
omarchy-shell io.github.layolayo.mc-4bars show
omarchy-shell io.github.layolayo.mc-4bars hide
omarchy-shell io.github.layolayo.mc-4bars toggleEdge bottom
omarchy-shell io.github.layolayo.mc-4bars toggleEdge left
omarchy-shell io.github.layolayo.mc-4bars toggleEdge right
omarchy-shell io.github.layolayo.mc-4bars toggleEdge top
omarchy-shell io.github.layolayo.mc-4bars swapEdges top bottom
omarchy-shell io.github.layolayo.mc-4bars reloadConfig
omarchy-shell io.github.layolayo.mc-4bars togglePlugin <plugin-id>
```

---

## Configuration Schema (`~/.config/omarchy/shell.json`)

All four bar slots share the same configuration structure in `~/.config/omarchy/shell.json`:

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "background": "none",
    "layout": {
      "left": [{ "id": "workspaces" }],
      "center": [{ "id": "clock" }],
      "right": [{ "id": "tray" }, { "id": "battery" }]
    }
  },
  "bottomBar": {
    "position": "bottom",
    "background": "none",
    "layout": {
      "left": [],
      "center": [{ "id": "voxtype" }],
      "right": []
    }
  },
  "leftBar": {
    "position": "left",
    "background": "none",
    "layout": {
      "left": [],
      "center": [],
      "right": []
    }
  },
  "rightBar": {
    "position": "right",
    "background": "none",
    "layout": {
      "left": [],
      "center": [],
      "right": []
    }
  },
  "plugins": [
    { "id": "io.github.layolayo.mc-4bars" }
  ]
}
```

---

## Licence

MIT Licence — Copyright (c) 2026 Matthew (`layolayo`).
