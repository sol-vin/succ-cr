# SUCC-CR — Source Engine Unofficial Character Controller (Crystal / Lapis Port)

**SUCC-CR** (`succ-cr`) is a native [Crystal](https://crystal-lang.org/) port of [**SUCC (Source Engine Unofficial Character Controller)**](https://github.com/bearlikelion/SUCC) built with the [**Lapis**](https://github.com/sol-vin/lapis) GDExtension framework for Godot 4.

> **Original Author & Repository Credit:**  
> This addon is a Crystal port of [**SUCC**](https://github.com/bearlikelion/SUCC), originally created in GDScript by [**bearlikelion** (Mark Arneman)](https://github.com/bearlikelion) & **Nerdiful**. All movement math, Quake/GoldSrc/Source physics parameters, presets, and controller architecture are credited to the original author.

---

## Features

- **Authentic Quake & Source Movement Physics** (`PM_Accelerate`, `PM_AirAccelerate`, `PM_Friction`, `PM_ClipVelocity`)
  - Ground acceleration, friction with `stop_speed` (`sv_stopspeed`), and slope velocity projection
  - Air strafing (`sv_airaccelerate` + `max_air_speed` wish-speed cap)
  - Bunny hopping (`bhop_buffered_jump` hold-to-bhop or manual frame-perfect bhop)
  - Ramp surfing on steep angled surfaces (`45.57°`–`80°`)
  - Per-axis velocity clamping (`sv_maxvelocity`)
- **Stair Stepping & View Smoothing**
  - Three-phase `test_move` sweep (up $\rightarrow$ forward $\rightarrow$ down) with raycast surface normal verification
  - Air-stepping onto ledges when falling
  - Downward stair snapping when walking down steps
  - Smooth camera vertical step interpolation (`WalkMove` style)
- **Crouching & Hull Management**
  - Standing (`BoxShape3D` or `CylinderShape3D`) and crouching collision hulls automatically built and updated in-editor (`@[Tool]`)
  - Source-style mid-air crouch (feet pull up while head stays in place)
  - Overhead shape-cast clearance check before uncrouching (`intersect_shape_into`)
  - Smooth cubic ease-out (`SMOOTH`) or instant (`SNAP`) crouch view transition
- **Camera Rig (`SUCCCamera`)**
  - First-person and third-person (`SpringArm3D`) camera modes
  - Quake/GoldSrc asymmetric triangle-wave view bob (`V_CalcBob`)
  - Quake lateral strafe camera roll (`V_CalcRoll`)
  - Source-style mouse sensitivity (`degrees_per_unit = 0.022`, `m_yaw`)
  - Physics tick camera interpolation for high-refresh-rate monitors
- **5 Ready-to-Use Engine Presets**
  - **Default (SUCC)** (`res://addons/succ_cr/resources/default_config.tres`)
  - **Quake (1996)** (`res://addons/succ_cr/resources/quake.tres`)
  - **Quake 2 (1997)** (`res://addons/succ_cr/resources/quake2.tres`)
  - **GoldSrc / Half-Life (1998)** (`res://addons/succ_cr/resources/goldsrc.tres`)
  - **Source / Half-Life 2 (2004)** (`res://addons/succ_cr/resources/source.tres`)
- **Multiplayer Pawn (`SUCCPawn`)**
  - Lightweight networked player representation for `MultiplayerSynchronizer` state interpolation

---

## Installation

### Via Lapis CLI

In any Lapis-powered Godot 4 project:

```bash
lapis install addon github:sol-vin/succ-cr
```

Or add `succ_cr` to your `shard.yml` dependencies and copy `addons/succ_cr` into your project's `addons/` folder:

```yaml
dependencies:
  succ_cr:
    github: sol-vin/succ-cr
    version: ~> 0.1.0
```

Then require it in your `src/main.cr`:

```crystal
require "succ_cr"
```

---

## Quick Start

### 1. Drop in the Character Scene

Instance `res://addons/succ_cr/scenes/succ_character.tscn` into your 3D level, or construct the node hierarchy manually:

```text
SUCC (CharacterBody3D)
└── SUCCCamera (SpringArm3D)
    └── Camera3D
```

`SUCC` automatically generates its standing and crouching `CollisionShape3D` nodes at runtime and in the Godot Editor.

### 2. Configure Input Map Actions

Ensure the following actions exist in **Project > Project Settings > Input Map** (or customize the action names in the `SUCC` Inspector under **Input Actions**):

| Action Property | Default Input Map Name | Suggested Binding |
| :--- | :--- | :--- |
| `action_move_forward` | `forward` | `W` |
| `action_move_backward` | `back` | `S` |
| `action_move_left` | `left` | `A` |
| `action_move_right` | `right` | `D` |
| `action_jump` | `jump` | `Space` |
| `action_crouch` | `crouch` | `Ctrl` |
| `action_sprint` | `sprint` | `Shift` |
| `action_camera_mode` | `camera_mode` | `V` |

---

## Engine Presets

Swap movement feel at edit-time via the `config` property in the Inspector or at runtime in Crystal:

```crystal
# Using pre-built .tres resources
player.config = SUCCConfig.new(Godot.load("res://addons/succ_cr/resources/quake.tres").pointer)

# Or using Crystal preset constructors
player.config = SUCCConfig.default_preset
player.config = SUCCConfig.quake_preset
player.config = SUCCConfig.quake2_preset
player.config = SUCCConfig.goldsrc_preset
player.config = SUCCConfig.source_preset
```

| Preset | Max Speed | Gravity | Jump Height | Friction | Air Accel | Auto Bhop | Crouch Mode |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Default (SUCC)** | `8.128 m/s` (320u) | `20.32 m/s²` (800u) | `1.128 m` (44.4u) | `4.0` | `10.0` | `true` | `SMOOTH` |
| **Quake (1996)** | `8.128 m/s` (320u) | `20.32 m/s²` (800u) | `1.158 m` (45.6u) | `6.0` | `10.0` | `false` | Disabled (`SNAP`) |
| **Quake 2 (1997)** | `7.620 m/s` (300u) | `20.32 m/s²` (800u) | `1.158 m` (45.6u) | `6.0` | `1.0` | `false` | `SNAP` |
| **GoldSrc (1998)** | `8.128 m/s` (320u) | `20.32 m/s²` (800u) | `1.128 m` (44.4u) | `4.0` | `10.0` | `false` | `SNAP` |
| **Source (2004)** | `4.826 m/s` (190u, Sprint 320u) | `15.24 m/s²` (600u) | `0.533 m` (21.0u) | `4.0` | `10.0` | `false` | `SMOOTH` |

### Unit Conversion Helpers

Source and Quake use inches (`1 meter = 39.37 units`):

```crystal
meters = SUCCConfig.source_units(320.0_f32) # => 8.128_f32
meters = SUCCConfig.quake_units(800.0_f32)  # => 20.32_f32
units  = SUCCConfig.to_source_units(1.829_f32) # => 72.0_f32
```

---

## Signals & States

### Signals on `SUCC`

- `movement_state_changed(old_state : SUCC::MovementState, new_state : SUCC::MovementState)`
- `game_state_changed(old_state : SUCC::GameState, new_state : SUCC::GameState)`
- `jumped()`
- `landed(impact_speed : Float64)`
- `camera_mode_changed(mode : SUCC::CameraMode)`

### Enums on `SUCC`

- `SUCC::MovementState`: `IDLE`, `WALKING`, `SPRINTING`, `CROUCHING`, `FALLING`, `SURFING`
- `SUCC::GameState`: `PLAYING`, `PAUSED`, `MENU`, `CUTSCENE`
- `SUCC::CameraMode`: `FIRST_PERSON`, `THIRD_PERSON`
- `SUCC::FloorType`: `NONE`, `GROUND`, `RAMP`

---

## Development & Testing

```bash
# Run Crystal unit specs
crystal spec

# Build the GDExtension shared library
lapis build
```

---

## Credits & License

- **Original GDScript Addon ([SUCC](https://github.com/bearlikelion/SUCC))**: Created by [**bearlikelion** (Mark Arneman)](https://github.com/bearlikelion) & **Nerdiful** (MIT License).
- **Crystal / Lapis Port ([succ-cr](https://github.com/sol-vin/succ-cr))**: Ported by [Ian Rash (Sol-Vin)](https://github.com/sol-vin) (MIT License).

See [LICENSE](LICENSE) for full license text.
