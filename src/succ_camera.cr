# Camera rig for SUCC (Source Engine Unofficial Character Controller).
#
# Extends SpringArm3D. Handles mouse look, first/third person switching,
# and view offsets (crouch, stair step smoothing, head bob, strafe tilt).
# Attach a Camera3D as a child of this node.
#
# Original GDScript implementation by Mark Arneman (bearlikelion) & Nerdiful:
# https://github.com/bearlikelion/SUCC
node SUCCCamera < SpringArm3D do
  # Emitted when camera mode changes (0 = FIRST_PERSON, 1 = THIRD_PERSON)
  signal mode_changed(mode : Int64)

  # Invert vertical mouse look
  @[Export]
  property invert_mouse_y : Bool = false

  # Node rotated horizontally (yaw). Usually the parent SUCC CharacterBody3D.
  @[Export]
  property yaw_target : Godot::Node3D? = nil

  property camera : Godot::Camera3D? = nil
  property step_offset : Float32 = 0.0_f32

  @base_y : Float32 = 0.0_f32
  @_physics_offset : Vector3 = Vector3.zero
  @_bob_offset : Float32 = 0.0_f32
  @_bob_time : Float32 = 0.0_f32
  @_tilt : Float32 = 0.0_f32

  def base_y : Float32
    @base_y
  end

  def base_y=(value : Float32) : Float32
    @base_y = value
    _apply_offsets
    @base_y
  end

  def _ready : Void
    @camera = _find_camera(self)
    if @camera.nil?
      Godot.log_warn("SUCCCamera", "No Camera3D found as child of SpringArm3D.")
    end
    @base_y = position.y
  end

  def _find_camera(n : Godot::Node) : Godot::Camera3D?
    return nil if n.pointer.null?
    count = n.get_child_count
    i = 0_i64
    while i < count
      child = n.get_child(i)
      if !child.pointer.null?
        if cam = child.as_a?(Godot::Camera3D)
          return cam
        end
        if found = _find_camera(child)
          return found
        end
      end
      i += 1
    end
    nil
  end

  def set_step_offset(offset : Float32) : Void
    @step_offset = offset
    _apply_offsets
  end

  def set_physics_offset(offset : Vector3) : Void
    @_physics_offset = offset
    _apply_offsets
  end

  # Quake/GoldSrc V_CalcBob: asymmetric triangle wave scaled by horizontal speed.
  def update_bob(horizontal_speed : Float32, on_floor : Bool, config : SUCCConfig, delta : Float32) : Void
    if config.bob_amount <= 0.0_f32 || !on_floor
      @_bob_offset = Math.move_toward(@_bob_offset, 0.0_f32, delta * 2.0_f32)
      _apply_offsets
      return
    end
    @_bob_time += delta
    cycle = @_bob_time - (@_bob_time / config.bob_cycle).floor * config.bob_cycle
    cycle /= config.bob_cycle
    if cycle < config.bob_up
      cycle = Math::PI.to_f32 * cycle / config.bob_up
    else
      cycle = Math::PI.to_f32 + Math::PI.to_f32 * (cycle - config.bob_up) / (1.0_f32 - config.bob_up)
    end
    bob = horizontal_speed * config.bob_amount
    bob = bob * 0.3_f32 + bob * 0.7_f32 * Math.sin(cycle)
    @_bob_offset = bob.clamp(-config.bob_max, config.bob_max)
    _apply_offsets
  end

  # Quake V_CalcRoll: roll camera proportional to lateral velocity.
  def update_tilt(vel : Vector3, basis_right : Vector3, config : SUCCConfig, delta : Float32) : Void
    if config.tilt_angle <= 0.0_f32
      if @_tilt != 0.0_f32
        @_tilt = 0.0_f32
        rot = rotation
        self.rotation = Vector3.new(rot.x, rot.y, 0.0_f32)
      end
      return
    end
    side = vel.dot(basis_right)
    sign_val = side < 0.0_f32 ? -1.0_f32 : (side > 0.0_f32 ? 1.0_f32 : 0.0_f32)
    side_abs = side.abs
    max_s = config.max_speed
    target_tilt = 0.0_f32
    if max_s > 0.0_f32
      if side_abs < max_s
        target_tilt = side_abs * config.tilt_angle / max_s
      else
        target_tilt = config.tilt_angle
      end
    end
    # Negate: Godot +Z rotation rolls left, Quake positive roll is right
    target_rad = -(target_tilt * sign_val) * (Math::PI.to_f32 / 180.0_f32)
    @_tilt = Math.lerp(@_tilt, target_rad, (delta * config.tilt_speed).clamp(0.0_f32, 1.0_f32))
    rot = rotation
    self.rotation = Vector3.new(rot.x, rot.y, @_tilt)
  end

  def _apply_offsets : Void
    self.position = Vector3.new(
      @_physics_offset.x,
      @base_y + @step_offset + @_bob_offset + @_physics_offset.y,
      @_physics_offset.z
    )
  end

  def handle_input(event : Godot::InputEvent, sensitivity : Float32, deg_per_unit : Float32) : Void
    if motion = event.as_a?(Godot::InputEventMouseMotion)
      if Godot::Input.mouse_mode == Godot::Input::MouseMode::MouseModeCaptured
        _apply_rotation(motion.relative, sensitivity, deg_per_unit)
      end
    end
  end

  def _apply_rotation(relative : Vector2, sensitivity : Float32, deg_per_unit : Float32) : Void
    deg_to_rad = Math::PI.to_f32 / 180.0_f32
    rad_per_dot = (sensitivity * deg_per_unit) * deg_to_rad
    yaw_delta = -relative.x * rad_per_dot
    pitch_sign = @invert_mouse_y ? 1.0_f32 : -1.0_f32
    pitch_delta = relative.y * rad_per_dot * pitch_sign

    rot = rotation
    max_pitch = 89.0_f32 * deg_to_rad
    new_pitch = (rot.x + pitch_delta).clamp(-max_pitch, max_pitch)
    self.rotation = Vector3.new(new_pitch, rot.y, rot.z)

    if target = @yaw_target
      if !target.pointer.null?
        target.rotate_y(yaw_delta.to_f64)
        return
      end
    end
    rotate_y(yaw_delta.to_f64)
  end

  # 0 = FIRST_PERSON, 1 = THIRD_PERSON
  def apply_mode(mode : Int64, third_person_dist : Float32) : Void
    if mode == 0_i64
      self.spring_length = 0.0_f64
    elsif mode == 1_i64
      self.spring_length = third_person_dist.to_f64
    end
    mode_changed.emit(mode)
  end
end
