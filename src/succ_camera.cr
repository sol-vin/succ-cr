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

  # Sit-state rotation constraint properties
  property yaw_constrained : Bool = false
  property accumulated_sit_yaw : Float32 = 0.0_f32
  property max_yaw_left_deg : Float32 = 80.0_f32
  property max_yaw_right_deg : Float32 = 80.0_f32
  property min_pitch_deg : Float32 = -60.0_f32
  property max_pitch_deg : Float32 = 60.0_f32

  @base_y : Float32 = 0.0_f32
  @_physics_offset : Vector3 = Vector3.zero
  @_bob_offset : Float32 = 0.0_f32
  @_bob_time : Float32 = 0.0_f32
  @_tilt : Float32 = 0.0_f32
  @_portal_rot_offset : Quaternion = Quaternion::IDENTITY
  @_portal_pos_offset : Vector3 = Vector3.zero

  def portal_rot_offset : Quaternion
    @_portal_rot_offset
  end

  def portal_pos_offset : Vector3
    @_portal_pos_offset
  end

  def has_active_portal_reorient? : Bool
    !@_portal_rot_offset.is_equal_approx(Quaternion::IDENTITY) || @_portal_pos_offset.length_squared > 1e-6_f32
  end

  # Converts a unit Quaternion into a Godot::Basis (where Basis.@x/@y/@z are matrix rows).
  def self.quaternion_to_basis(q : Quaternion) : Basis
    qn = q.is_normalized? ? q : q.normalized
    d = qn.length_squared
    return Basis::IDENTITY if d <= 1e-8_f32
    s = 2.0_f32 / d
    xs = qn.x * s
    ys = qn.y * s
    zs = qn.z * s
    wx = qn.w * xs
    wy = qn.w * ys
    wz = qn.w * zs
    xx = qn.x * xs
    xy = qn.x * ys
    xz = qn.x * zs
    yy = qn.y * ys
    yz = qn.y * zs
    zz = qn.z * zs
    Basis.new(
      Vector3.new(1.0_f32 - (yy + zz), xy - wz, xz + wy),
      Vector3.new(xy + wz, 1.0_f32 - (xx + zz), yz - wx),
      Vector3.new(xz - wy, yz + wx, 1.0_f32 - (xx + yy))
    )
  end

  # Converts an orthonormalized Godot::Basis into a unit Quaternion using Shepperd's method.
  def self.basis_to_quaternion(b_in : Basis) : Quaternion
    b = b_in.orthonormalized
    m00 = b.x.x; m01 = b.x.y; m02 = b.x.z
    m10 = b.y.x; m11 = b.y.y; m12 = b.y.z
    m20 = b.z.x; m21 = b.z.y; m22 = b.z.z
    trace = m00 + m11 + m22
    if trace > 0.0_f32
      s = Math.sqrt(trace + 1.0_f32)
      w = s * 0.5_f32
      s = 0.5_f32 / s
      Quaternion.new((m21 - m12) * s, (m02 - m20) * s, (m10 - m01) * s, w).normalized
    elsif m00 >= m11 && m00 >= m22
      s = Math.sqrt(1.0_f32 + m00 - m11 - m22)
      x = s * 0.5_f32
      s = 0.5_f32 / s
      Quaternion.new(x, (m10 + m01) * s, (m02 + m20) * s, (m21 - m12) * s).normalized
    elsif m11 >= m22
      s = Math.sqrt(1.0_f32 + m11 - m00 - m22)
      y = s * 0.5_f32
      s = 0.5_f32 / s
      Quaternion.new((m10 + m01) * s, y, (m21 + m12) * s, (m02 - m20) * s).normalized
    else
      s = Math.sqrt(1.0_f32 + m22 - m00 - m11)
      z = s * 0.5_f32
      s = 0.5_f32 / s
      Quaternion.new((m02 + m20) * s, (m21 + m12) * s, z, (m10 - m01) * s).normalized
    end
  end

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
    if @base_y.abs <= 1e-5_f32 && position.y > 1e-4_f32
      @base_y = position.y
    end
    self.position = Vector3.new(
      @_physics_offset.x + @_portal_pos_offset.x,
      @base_y + @step_offset + @_bob_offset + @_physics_offset.y + @_portal_pos_offset.y,
      @_physics_offset.z + @_portal_pos_offset.z
    )
  end

  def _apply_portal_camera_rotation : Void
    cam = @camera
    if cam.nil? && !@pointer.null?
      cam = _find_camera(self)
      @camera = cam
    end
    if c = cam
      if !c.pointer.null?
        c.basis = SUCCCamera.quaternion_to_basis(@_portal_rot_offset)
      end
    end
  end

  # Sets the initial 3D rotational and local positional offsets immediately after crossing an angled portal.
  def set_portal_transition_offsets(rot_offset : Quaternion, local_pos_offset : Vector3) : Void
    @_portal_rot_offset = rot_offset.is_finite? ? rot_offset.normalized : Quaternion::IDENTITY
    @_portal_pos_offset = local_pos_offset.is_finite? ? local_pos_offset : Vector3.zero
    _apply_offsets
    _apply_portal_camera_rotation
  end

  # Immediately clears any active portal transition rotation/position offsets.
  def clear_portal_transition_offsets : Void
    @_portal_rot_offset = Quaternion::IDENTITY
    @_portal_pos_offset = Vector3.zero
    _apply_offsets
    _apply_portal_camera_rotation
  end

  # Smoothly decays the portal transition rotational offset (via quaternion slerp to IDENTITY)
  # and local positional offset (via exponential lerp to ZERO) toward the upright world horizon.
  def update_portal_reorient(config : SUCCConfig, delta : Float32) : Void
    if !config.portal_smooth_reorient
      if has_active_portal_reorient?
        clear_portal_transition_offsets
      end
      return
    end

    rot_changed = false
    if !@_portal_rot_offset.is_equal_approx(Quaternion::IDENTITY)
      alpha_rot = (1.0_f32 - Math.exp(-config.portal_reorient_speed * delta)).clamp(0.0_f32, 1.0_f32)
      @_portal_rot_offset = @_portal_rot_offset.slerp(Quaternion::IDENTITY, alpha_rot).normalized
      if @_portal_rot_offset.get_angle.abs < 0.0005_f32
        @_portal_rot_offset = Quaternion::IDENTITY
      end
      rot_changed = true
    end

    pos_changed = false
    if @_portal_pos_offset.length_squared > 1e-7_f32
      alpha_pos = (1.0_f32 - Math.exp(-config.portal_pos_smooth_speed * delta)).clamp(0.0_f32, 1.0_f32)
      @_portal_pos_offset = @_portal_pos_offset.lerp(Vector3.zero, alpha_pos)
      if @_portal_pos_offset.length_squared <= 1e-7_f32
        @_portal_pos_offset = Vector3.zero
      end
      pos_changed = true
    end

    _apply_offsets if pos_changed
    _apply_portal_camera_rotation if rot_changed
  end

  # Returns the effective world-space camera transform including any active portal rotational/positional offsets.
  def effective_camera_global_transform : Transform3D
    cam = @camera
    if cam.nil? && !@pointer.null?
      cam = _find_camera(self)
      @camera = cam
    end
    if c = cam
      if !c.pointer.null?
        return c.global_transform
      end
    end
    rig_xf = global_transform
    Transform3D.new(
      (rig_xf.basis * SUCCCamera.quaternion_to_basis(@_portal_rot_offset)).orthonormalized,
      rig_xf.origin
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
    min_pitch = @yaw_constrained ? (@min_pitch_deg * deg_to_rad) : (-89.0_f32 * deg_to_rad)
    max_pitch = @yaw_constrained ? (@max_pitch_deg * deg_to_rad) : (89.0_f32 * deg_to_rad)
    new_pitch = (rot.x + pitch_delta).clamp(min_pitch, max_pitch)
    self.rotation = Vector3.new(new_pitch, rot.y, rot.z)

    if @yaw_constrained
      min_yaw = -(@max_yaw_right_deg.abs * deg_to_rad)
      max_yaw = @max_yaw_left_deg.abs * deg_to_rad
      clamped_yaw = (@accumulated_sit_yaw + yaw_delta).clamp(min_yaw, max_yaw)
      yaw_delta = clamped_yaw - @accumulated_sit_yaw
      @accumulated_sit_yaw = clamped_yaw
    end

    if @_portal_pos_offset.length_squared > 1e-7_f32 && yaw_delta.abs > 1e-6_f32
      @_portal_pos_offset = Basis.from_axis_angle(Vector3::UP, -yaw_delta) * @_portal_pos_offset
      _apply_offsets
    end

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
