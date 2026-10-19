# Configuration resource for SUCC (Source Engine Unofficial Character Controller).
#
# Stores all tunable movement, physics, collider, camera, head bob, and mouse parameters.
# Swap resources at runtime to change movement feel (e.g., Quake, Quake 2, GoldSrc, Source).
#
# Original GDScript implementation by Mark Arneman (bearlikelion) & Nerdiful:
# https://github.com/bearlikelion/SUCC
@[Tool]
resource SUCCConfig < Resource do
  # Conversion multiplier: 1 meter = 39.37 Source/Quake units (inches)
  SOURCE_MULT = 39.37_f32

  enum CrouchTransitionMode : Int64
    SMOOTH = 0
    SNAP   = 1
  end

  # ===========================================================================
  # Gravity & Jump
  # ===========================================================================
  @[ExportGroup("Gravity & Jump")]

  # Downward acceleration (800 u/s²)
  @[Export(suffix: "m/s²")]
  property gravity : Float32 = 20.32_f32

  # Target apex height using v = sqrt(2 * g * h) (~44.4u, matches 268 u/s at 800g)
  @[Export(suffix: "m")]
  property jump_height : Float32 = 1.128_f32

  # Hold jump to auto-jump on the landing frame (bunny hop)
  @[Export]
  property bhop_buffered_jump : Bool = true

  # ===========================================================================
  # Ground Movement
  # ===========================================================================
  @[ExportGroup("Ground Movement")]

  # Ground acceleration multiplier (sv_accelerate)
  @[Export]
  property acceleration : Float32 = 10.0_f32

  # Ground friction multiplier (sv_friction)
  @[Export]
  property friction : Float32 = 4.0_f32

  # Below this speed, friction uses this value instead (sv_stopspeed, 100 u/s)
  @[Export(suffix: "m/s")]
  property stop_speed : Float32 = 2.54_f32

  # Maximum ground movement speed (sv_maxspeed, 320 u/s)
  @[Export(suffix: "m/s")]
  property max_speed : Float32 = 8.128_f32

  # ===========================================================================
  # Air Movement
  # ===========================================================================
  @[ExportGroup("Air Movement")]

  # Air acceleration multiplier (sv_airaccelerate)
  @[Export]
  property air_acceleration : Float32 = 10.0_f32

  # Maximum wish speed in air - key to airstrafing (30 u/s)
  @[Export(suffix: "m/s")]
  property max_air_speed : Float32 = 0.762_f32

  # Per-axis velocity cap when enforce_max_velocity is enabled (sv_maxvelocity, 3500 u/s)
  @[Export(suffix: "m/s")]
  property max_velocity : Float32 = 88.9_f32

  # Clamp velocity per-axis to max_velocity each tick (sv_maxvelocity)
  @[Export]
  property enforce_max_velocity : Bool = false

  # ===========================================================================
  # Speed Modifiers
  # ===========================================================================
  @[ExportGroup("Speed Modifiers")]

  # Multiplier applied to max_speed while crouching (Source = 0.33)
  @[ExportRange(0.0_f32, 1.0_f32, 0.01_f32, suffix: "×")]
  property crouch_speed_modifier : Float32 = 0.33_f32

  # Multiplier applied to max_speed while sprinting
  @[ExportRange(1.0_f32, 3.0_f32, 0.05_f32, suffix: "×")]
  property sprint_speed_modifier : Float32 = 1.3_f32

  # ===========================================================================
  # Collider
  # ===========================================================================
  @[ExportGroup("Collider")]

  # Standing hull height (72u)
  @[Export(suffix: "m")]
  property stand_height : Float32 = 1.829_f32

  # Crouching hull height (36u)
  @[Export(suffix: "m")]
  property crouch_height : Float32 = 0.914_f32

  # Hull width / diameter (32u)
  @[Export(suffix: "m")]
  property width : Float32 = 0.813_f32

  # Maximum stair step height (sv_stepsize, 18u)
  @[Export(suffix: "m")]
  property step_height : Float32 = 0.457_f32

  def stand_height=(val : Float32) : Float32
    unless (@stand_height - val).abs < 0.00001_f32
      @stand_height = val
      emit_changed if !@pointer.null?
    end
    @stand_height
  end

  def crouch_height=(val : Float32) : Float32
    unless (@crouch_height - val).abs < 0.00001_f32
      @crouch_height = val
      emit_changed if !@pointer.null?
    end
    @crouch_height
  end

  def width=(val : Float32) : Float32
    unless (@width - val).abs < 0.00001_f32
      @width = val
      emit_changed if !@pointer.null?
    end
    @width
  end

  def step_height=(val : Float32) : Float32
    unless (@step_height - val).abs < 0.00001_f32
      @step_height = val
      emit_changed if !@pointer.null?
    end
    @step_height
  end

  # ===========================================================================
  # Camera
  # ===========================================================================
  @[ExportGroup("Camera")]

  # Eye height from feet when standing (64u)
  @[Export(suffix: "m")]
  property standing_view_offset : Float32 = 1.626_f32

  # Eye height from feet when crouched (28u)
  @[Export(suffix: "m")]
  property crouch_view_offset : Float32 = 0.711_f32

  # Smooth (Source/HL2) or instant snap (Quake) crouch view transition
  @[Export]
  property crouch_transition_mode : CrouchTransitionMode = CrouchTransitionMode::SMOOTH

  # Tween speed when crouching (higher = faster, 10 = ~0.2s duration)
  @[ExportRange(1.0_f32, 30.0_f32, 0.5_f32)]
  property crouch_smoothing_speed : Float32 = 10.0_f32

  # Tween speed when uncrouching (higher = faster, 7 = ~0.29s duration)
  @[ExportRange(1.0_f32, 30.0_f32, 0.5_f32)]
  property uncrouch_smoothing_speed : Float32 = 7.0_f32

  # SpringArm3D length in third-person mode
  @[Export(suffix: "m")]
  property third_person_distance : Float32 = 3.5_f32

  # Smoothly interpolate camera Y across stair steps (Source WalkMove style)
  @[Export]
  property smooth_vertical_step : Bool = true

  # How fast the stair step camera offset decays
  @[ExportRange(1.0_f32, 30.0_f32, 0.5_f32)]
  property step_smoothing_speed : Float32 = 14.0_f32

  # ===========================================================================
  # Head Bob & Tilt
  # ===========================================================================
  @[ExportGroup("Head Bob & Tilt")]

  # View bob amplitude multiplier (cl_bob, 0 = disabled)
  @[ExportRange(0.0_f32, 0.05_f32, 0.001_f32)]
  property bob_amount : Float32 = 0.01_f32

  # View bob period in seconds (cl_bobcycle)
  @[ExportRange(0.1_f32, 2.0_f32, 0.05_f32, suffix: "s")]
  property bob_cycle : Float32 = 0.65_f32

  # Asymmetry of bob wave (cl_bobup, 0.5 = symmetric sine)
  @[ExportRange(0.0_f32, 1.0_f32, 0.05_f32)]
  property bob_up : Float32 = 0.5_f32

  # Maximum view bob offset in meters (~4u)
  @[ExportRange(0.0_f32, 0.5_f32, 0.01_f32, suffix: "m")]
  property bob_max : Float32 = 0.1_f32

  # Camera roll angle when strafing (cl_rollangle, 0 = disabled)
  @[ExportRange(0.0_f32, 10.0_f32, 0.5_f32, suffix: "°")]
  property tilt_angle : Float32 = 1.5_f32

  # How fast camera roll interpolates
  @[ExportRange(1.0_f32, 20.0_f32, 0.5_f32)]
  property tilt_speed : Float32 = 8.0_f32

  # ===========================================================================
  # Mouse
  # ===========================================================================
  @[ExportGroup("Mouse")]

  # Mouse sensitivity multiplier (Source default = 3.0)
  @[ExportRange(0.1_f32, 20.0_f32, 0.1_f32)]
  property mouse_sensitivity : Float32 = 2.5_f32

  # Degrees rotated per mouse count at sensitivity 1.0 (m_yaw = 0.022)
  @[ExportRange(0.001_f32, 0.1_f32, 0.001_f32, suffix: "°")]
  property degrees_per_unit : Float32 = 0.022_f32

  # ===========================================================================
  # Unit Conversion & Preset Helpers
  # ===========================================================================

  # Convert Source/Quake units to meters (Godot units).
  # Example: `SUCCConfig.source_units(320.0_f32)` -> `8.128_f32`
  def self.source_units(value : Float32) : Float32
    value / SOURCE_MULT
  end

  # Alias for `source_units` - Quake and Source share the same unit scale.
  def self.quake_units(value : Float32) : Float32
    value / SOURCE_MULT
  end

  # Convert meters (Godot units) to Source/Quake units.
  def self.to_source_units(meters : Float32) : Float32
    meters * SOURCE_MULT
  end

  # Creates a new SUCCConfig configured with the Default SUCC preset.
  def self.default_preset : SUCCConfig
    cfg = Godot::Bridge.init_done? ? SUCCConfig.create : SUCCConfig.new
    cfg
  end

  # Creates a new SUCCConfig configured with the Quake (1996) preset.
  def self.quake_preset : SUCCConfig
    cfg = Godot::Bridge.init_done? ? SUCCConfig.create : SUCCConfig.new
    cfg.jump_height = 1.158_f32
    cfg.bhop_buffered_jump = false
    cfg.friction = 6.0_f32
    cfg.max_velocity = 50.8_f32
    cfg.enforce_max_velocity = true
    cfg.stand_height = 1.422_f32
    cfg.crouch_height = 1.422_f32
    cfg.standing_view_offset = 1.27_f32
    cfg.crouch_view_offset = 1.27_f32
    cfg.crouch_transition_mode = CrouchTransitionMode::SNAP
    cfg.smooth_vertical_step = false
    cfg.bob_amount = 0.02_f32
    cfg.bob_cycle = 0.6_f32
    cfg.tilt_angle = 2.0_f32
    cfg
  end

  # Creates a new SUCCConfig configured with the Quake 2 (1997) preset.
  def self.quake2_preset : SUCCConfig
    cfg = Godot::Bridge.init_done? ? SUCCConfig.create : SUCCConfig.new
    cfg.jump_height = 1.158_f32
    cfg.bhop_buffered_jump = false
    cfg.friction = 6.0_f32
    cfg.max_speed = 7.62_f32
    cfg.air_acceleration = 1.0_f32
    cfg.max_air_speed = 7.62_f32
    cfg.max_velocity = 50.8_f32
    cfg.enforce_max_velocity = true
    cfg.crouch_speed_modifier = 0.5_f32
    cfg.stand_height = 1.422_f32
    cfg.crouch_height = 0.813_f32
    cfg.standing_view_offset = 1.168_f32
    cfg.crouch_view_offset = 0.457_f32
    cfg.crouch_transition_mode = CrouchTransitionMode::SNAP
    cfg.smooth_vertical_step = false
    cfg.bob_amount = 0.005_f32
    cfg.bob_cycle = 0.8_f32
    cfg.tilt_angle = 0.0_f32
    cfg
  end

  # Creates a new SUCCConfig configured with the GoldSrc / Half-Life (1998) preset.
  def self.goldsrc_preset : SUCCConfig
    cfg = Godot::Bridge.init_done? ? SUCCConfig.create : SUCCConfig.new
    cfg.jump_height = 1.128_f32
    cfg.bhop_buffered_jump = false
    cfg.max_velocity = 50.8_f32
    cfg.enforce_max_velocity = true
    cfg.crouch_transition_mode = CrouchTransitionMode::SNAP
    cfg.smooth_vertical_step = false
    cfg.bob_cycle = 0.8_f32
    cfg.tilt_angle = 2.0_f32
    cfg
  end

  # Creates a new SUCCConfig configured with the Source / Half-Life 2 (2004) preset.
  def self.source_preset : SUCCConfig
    cfg = Godot::Bridge.init_done? ? SUCCConfig.create : SUCCConfig.new
    cfg.gravity = 15.24_f32
    cfg.jump_height = 0.533_f32
    cfg.bhop_buffered_jump = false
    cfg.max_speed = 4.826_f32
    cfg.enforce_max_velocity = true
    cfg.sprint_speed_modifier = 1.684_f32
    cfg.bob_amount = 0.0_f32
    cfg.bob_cycle = 0.8_f32
    cfg.tilt_angle = 0.0_f32
    cfg
  end
end
