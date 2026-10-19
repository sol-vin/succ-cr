# Demo test level controller for SUCC (Crystal Port).
#
# Provides runtime preset switching (keys 1-5), speedometer HUD updates
# (Source/Quake u/s and m/s), jump counter, and jump audio feedback.
#
# Original GDScript implementation by Mark Arneman (bearlikelion) & Nerdiful:
# https://github.com/bearlikelion/SUCC
node SUCCTestLevel < Node3D do
  PRESET_NAMES = [
    "Default (SUCC)",
    "Quake (1996)",
    "Quake 2 (1997)",
    "GoldSrc / Half-Life (1998)",
    "Source / Half-Life 2 (2004)",
  ]

  PRESET_PATHS = [
    "res://addons/succ_cr/resources/default_config.tres",
    "res://addons/succ_cr/resources/quake.tres",
    "res://addons/succ_cr/resources/quake2.tres",
    "res://addons/succ_cr/resources/goldsrc.tres",
    "res://addons/succ_cr/resources/source.tres",
  ]

  onready character : SUCC? = "%Player"
  onready units_label : Godot::Label? = "%UnitsLabel"
  onready metric_label : Godot::Label? = "%MetricLabel"
  onready state_label : Godot::Label? = "%StateLabel"
  onready preset_label : Godot::Label? = "%PresetLabel"
  onready preset_detail : Godot::Label? = "%PresetDetail"
  onready flags_label : Godot::Label? = "%FlagsLabel"
  onready hint_label : Godot::Label? = "%Hint"
  onready jump_sound : Godot::AudioStreamPlayer? = "%JumpSound"

  @_current_preset : Int32 = 0
  @_jump_count : Int32 = 0

  def _ready : Void
    if char_node = @character
      char_node.jumped.connect { _on_jumped }
    end
    if hint = @hint_label
      hint.text = "WASD: Move  |  Space: Jump  |  Shift: Sprint  |  Ctrl: Crouch  |  1-5: Presets  |  V: Camera  |  Esc: Pause"
    end
    _apply_preset(0)
  end

  def _unhandled_input(event : Godot::InputEvent) : Void
    if key_ev = event.as_a?(Godot::InputEventKey)
      if key_ev.pressed? && !key_ev.echo?
        keycode = key_ev.keycode
        if keycode == Godot::Key::Escape
          if char_node = @character
            if char_node.game_state == SUCC::GameState::PLAYING
              char_node.set_game_state(SUCC::GameState::PAUSED)
            else
              char_node.set_game_state(SUCC::GameState::PLAYING)
            end
          end
        elsif keycode >= Godot::Key::Val1 && keycode <= Godot::Key::Val5
          idx = (keycode.value - Godot::Key::Val1.value).to_i32
          _apply_preset(idx)
        end
      end
    end
  end

  def _apply_preset(index : Int32) : Void
    return if index < 0 || index >= PRESET_NAMES.size
    @_current_preset = index

    cfg : SUCCConfig? = nil
    path = PRESET_PATHS[index]
    if !@pointer.null?
      loaded = Godot.load(path)
      if loaded && !loaded.pointer.null?
        if alive = Godot::Bridge.find_alive_instance(loaded.pointer).as?(SUCCConfig)
          cfg = alive
        else
          cfg = SUCCConfig.new(loaded.pointer)
        end
      end
    end

    if cfg.nil?
      cfg = case index
            when 0 then SUCCConfig.default_preset
            when 1 then SUCCConfig.quake_preset
            when 2 then SUCCConfig.quake2_preset
            when 3 then SUCCConfig.goldsrc_preset
            when 4 then SUCCConfig.source_preset
            else        SUCCConfig.default_preset
            end
    end

    active_cfg = cfg.not_nil!
    if char_node = @character
      char_node.config = active_cfg
    end

    if lbl = @preset_label
      lbl.text = "[#{index + 1}] #{PRESET_NAMES[index]}"
    end

    if detail = @preset_detail
      detail.text = String.build do |io|
        io << "Speed: #{(active_cfg.max_speed * SUCCConfig::SOURCE_MULT).round.to_i}u (#{"%.1f" % active_cfg.max_speed} m/s)  |  "
        io << "Accel: #{active_cfg.acceleration.round.to_i}  |  "
        io << "AirAccel: #{active_cfg.air_acceleration.round.to_i}  |  "
        io << "Friction: #{active_cfg.friction.round.to_i}\n"
        io << "Gravity: #{(active_cfg.gravity * SUCCConfig::SOURCE_MULT).round.to_i}u  |  "
        io << "Jump: #{(active_cfg.jump_height * SUCCConfig::SOURCE_MULT).round.to_i}u (#{"%.2f" % active_cfg.jump_height}m)  |  "
        io << "Hull: #{(active_cfg.width * SUCCConfig::SOURCE_MULT).round.to_i}x#{(active_cfg.stand_height * SUCCConfig::SOURCE_MULT).round.to_i}u  |  "
        io << "Bhop: #{active_cfg.bhop_buffered_jump ? "Auto" : "Manual"}"
      end
    end
  end

  def _on_jumped : Void
    @_jump_count += 1
    if sfx = @jump_sound
      sfx.play if !sfx.pointer.null?
    end
  end

  def _process(delta : Float64) : Void
    char_node = @character
    return unless char_node && !char_node.pointer.null?

    vel = char_node.velocity
    horiz = Vector2.new(vel.x, vel.z).length
    units_per_sec = horiz * SUCCConfig::SOURCE_MULT

    if u_lbl = @units_label
      u_lbl.text = "#{units_per_sec.round.to_i} u/s"
    end
    if m_lbl = @metric_label
      m_lbl.text = "#{"%.1f" % horiz} m/s  |  Y: #{"%.1f" % vel.y} m/s"
    end
    if s_lbl = @state_label
      s_lbl.text = "#{char_node.get_movement_state_name}  |  Floor: #{char_node.get_floor_type_name}"
    end
    if f_lbl = @flags_label
      f_lbl.text = "Sprint: #{char_node.sprint_enabled ? "ON" : "OFF"}  |  Crouch: #{char_node.crouch_enabled ? "ON" : "OFF"}  |  Lean: #{char_node.lean_enabled ? "ON" : "OFF"}  |  Jumps: #{@_jump_count}"
    end
  end
end
