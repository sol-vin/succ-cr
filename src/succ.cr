# SUCC - Source Engine Unofficial Character Controller (Crystal Port for Lapis)
#
# Full-featured 3D character controller implementing Quake/Source engine movement
# physics: ground/air acceleration, airstrafing, bunny hopping, surf ramps,
# stair stepping (ground + air), source-style air crouch, view bob & strafe tilt,
# and first/third person camera switching.
#
# Original GDScript implementation by Mark Arneman (bearlikelion) & Nerdiful:
# https://github.com/bearlikelion/SUCC
node SUCC < CharacterBody3D do
  # Maximum angle (degrees) for surf ramps; steeper = wall
  SURF_MAX_ANGLE = 60.0_f32

  enum CameraMode : Int64
    FIRST_PERSON = 0
    THIRD_PERSON = 1
  end

  enum FloorType : Int64
    NONE   = 0
    GROUND = 1
    RAMP   = 2
  end

  enum MovementState : Int64
    IDLE      = 0
    WALKING   = 1
    SPRINTING = 2
    CROUCHING = 3
    FALLING   = 4
    SURFING   = 5
    SITTING   = 6
  end

  enum GameState : Int64
    PLAYING  = 0
    PAUSED   = 1
    MENU     = 2
    CUTSCENE = 3
    DEAD     = 4
  end

  # ===========================================================================
  # Signals
  # ===========================================================================
  signal movement_state_changed(old_state : MovementState, new_state : MovementState)
  signal game_state_changed(old_state : GameState, new_state : GameState)
  signal jumped
  signal landed(fall_velocity : Float64)
  signal camera_mode_changed(mode : CameraMode)
  signal sat_down(chair : Godot::Node3D)
  signal stood_up
  signal interacted(target : Godot::Object)

  # ===========================================================================
  # Exports
  # ===========================================================================

  # Movement configuration resource. If nil, a default SUCCConfig is created in _ready.
  @[Export]
  property config : SUCCConfig? = nil

  # Optional NodePath string to a visual mesh root hidden in first-person mode.
  @[Export]
  property visual_root_path : String = ""

  # Initial / active camera mode (FIRST_PERSON or THIRD_PERSON).
  @[Export]
  property camera_mode : CameraMode = CameraMode::FIRST_PERSON

  # Current high-level game state controlling input & mouse look.
  @[Export]
  property game_state : GameState = GameState::PLAYING

  # Allow sprinting
  @[Export]
  property sprint_enabled : Bool = true

  # Allow crouching
  @[Export]
  property crouch_enabled : Bool = true

  # Allow leaning (reserved)
  @[Export]
  property lean_enabled : Bool = false

  # Use CylinderShape3D instead of BoxShape3D for hull colliders.
  # Cylinders are smoother on curved surfaces; boxes are authentic to Quake/Source.
  @[Export]
  property use_cylinders : Bool = false

  # ===========================================================================
  # Input Action Mapping Exports
  # ===========================================================================
  @[ExportGroup("Input Actions")]

  @[Export]
  property action_move_forward : String = "forward"

  @[Export]
  property action_move_backward : String = "back"

  @[Export]
  property action_move_left : String = "left"

  @[Export]
  property action_move_right : String = "right"

  @[Export]
  property action_jump : String = "jump"

  @[Export]
  property action_crouch : String = "crouch"

  @[Export]
  property action_sprint : String = "sprint"

  @[Export]
  property action_camera_mode : String = "camera_mode"

  @[Export]
  property action_interact : String = "interact"

  # Maximum reach distance in meters for the player interaction raycast.
  @[Export(range: 0.5_f32..15.0_f32, step: 0.25_f32)]
  property interact_distance : Float32 = 3.0_f32

  # Dictionary mapping internal action keys to Godot InputMap action names.
  property input_actions : Hash(String, String) = {
    "move_forward"  => "forward",
    "move_backward" => "back",
    "move_left"     => "left",
    "move_right"    => "right",
    "jump"          => "jump",
    "crouch"        => "crouch",
    "sprint"        => "sprint",
    "camera_mode"   => "camera_mode",
    "interact"      => "interact",
  }

  # ===========================================================================
  # Runtime State
  # ===========================================================================
  property camera_rig : SUCCCamera? = nil
  property interact_ray : Godot::RayCast3D? = nil
  property visual_root : Godot::Node3D? = nil
  property standing_collider : Godot::CollisionShape3D? = nil
  property crouching_collider : Godot::CollisionShape3D? = nil

  property floor_type : FloorType = FloorType::NONE
  property surf_normal : Vector3 = Vector3::UP
  property is_crouched : Bool = false
  property is_sitting : Bool = false
  property loading_blocked : Bool = false
  property pre_sit_transform : Transform3D = Transform3D::IDENTITY
  property active_chair : Godot::Node3D? = nil
  property focused_interactable : Godot::Node? = nil
  property movement_state : MovementState = MovementState::IDLE

  @_teleport_queued : Bool = false
  @_teleport_from : Godot::Node3D? = nil
  @_teleport_to : Godot::Node3D? = nil

  @_was_on_floor : Bool = false
  @_step_Lists_offset : Float32 = 0.0_f32
  @_just_jumped : Bool = false
  @_pre_move_y_vel : Float32 = 0.0_f32
  property _phys_pos_prev : Vector3 = Vector3.zero
  property _phys_pos_curr : Vector3 = Vector3.zero

  # Smooth crouch view transition state (cubic ease-out)
  @_crouch_tween_active : Bool = false
  @_crouch_tween_elapsed : Float32 = 0.0_f32
  @_crouch_tween_duration : Float32 = 0.2_f32
  @_crouch_tween_start_y : Float32 = 1.626_f32
  @_crouch_tween_target_y : Float32 = 1.626_f32

  # Cached physics query objects to avoid per-frame allocations
  @_up_collision : Godot::KinematicCollision3D? = nil
  @_fwd_collision : Godot::KinematicCollision3D? = nil
  @_down_collision : Godot::KinematicCollision3D? = nil
  @_ray_query : Godot::PhysicsRayQueryParameters3D? = nil
  @_ray_result : Godot::PhysicsIntersectRayResult3D? = nil
  @_shape_query : Godot::PhysicsShapeQueryParameters3D? = nil
  @_shape_result : Godot::PhysicsIntersectShapeResult3D? = nil

  # Custom setter for config: rebuilds collider shapes when swapped at runtime
  def config=(val : SUCCConfig?) : SUCCConfig?
    @config = val
    if cfg = @config
      if !@pointer.null? && is_inside_tree
        _rebuild_shapes
        if rig = @camera_rig
          rig.base_y = @is_crouched ? cfg.crouch_view_offset : cfg.standing_view_offset
        end
      end
    end
    @config
  end

  def camera_mode=(val : CameraMode) : CameraMode
    set_camera_mode(val)
    @camera_mode
  end

  def game_state=(val : GameState) : GameState
    set_game_state(val)
    @game_state
  end

  def active_config : SUCCConfig
    if cfg = @config
      cfg
    else
      new_cfg = !@pointer.null? ? SUCCConfig.create : SUCCConfig.new
      @config = new_cfg
      new_cfg
    end
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  def _ready : Void
    if @config.nil?
      @config = !@pointer.null? ? SUCCConfig.create : SUCCConfig.new
    end

    _sync_input_actions_from_exports
    _validate_input_actions
    _setup_colliders
    @camera_rig = _find_camera_rig
    _setup_interact_ray

    cfg = active_config
    if rig = @camera_rig
      if rig.yaw_target.nil?
        rig.yaw_target = self
      end
      rig.base_y = cfg.standing_view_offset
      rig.apply_mode(@camera_mode.value, cfg.third_person_distance)
    else
      Godot.log_warn("SUCC", "No SUCCCamera found as child. Add a SpringArm3D with SUCCCamera and a Camera3D child.")
    end

    if !@visual_root_path.empty?
      node = get_node_or_null(@visual_root_path)
      if node && !node.pointer.null?
        @visual_root = node.as_a?(Godot::Node3D)
      end
    end

    set_camera_mode(@camera_mode)
    Godot::Input.mouse_mode = Godot::Input::MouseMode::MouseModeCaptured

    self.floor_constant_speed = false
    self.floor_stop_on_slope = true
    self.floor_max_angle = 45.573_f64 * (Math::PI / 180.0) # acos(0.7) - matches Source
    self.floor_snap_length = 0.0_f64                       # Manual step-down handles stairs

    @_phys_pos_prev = global_position
    @_phys_pos_curr = global_position

    # Pre-allocate reusable physics query wrappers
    @_up_collision = Godot::KinematicCollision3D.create
    @_fwd_collision = Godot::KinematicCollision3D.create
    @_down_collision = Godot::KinematicCollision3D.create
    @_ray_query = Godot.create(Godot::PhysicsRayQueryParameters3D)
    @_ray_result = Godot::PhysicsIntersectRayResult3D.create
    @_shape_query = Godot::PhysicsShapeQueryParameters3D.create
    @_shape_result = Godot::PhysicsIntersectShapeResult3D.create
  end

  def _process(delta : Float64) : Void
    dt = delta.to_f32
    cfg = active_config

    # Advance crouch view transition if active
    if @_crouch_tween_active
      @_crouch_tween_elapsed += dt
      t = (@_crouch_tween_elapsed / @_crouch_tween_duration).clamp(0.0_f32, 1.0_f32)
      # Cubic ease-out: 1 - (1 - t)^3
      inv = 1.0_f32 - t
      ease_t = 1.0_f32 - (inv * inv * inv)
      if rig = @camera_rig
        rig.base_y = Math.lerp(@_crouch_tween_start_y, @_crouch_tween_target_y, ease_t)
      end
      if t >= 1.0_f32
        @_crouch_tween_active = false
      end
    end

    _smooth_camera_step(dt)
    if rig = @camera_rig
      # Manual physics interpolation: blend camera between previous and current physics ticks
      frac = Godot::Engine.get_physics_interpolation_fraction.to_f32
      interp_pos = @_phys_pos_prev.lerp(@_phys_pos_curr, frac)
      world_offset = interp_pos - global_position
      rig.set_physics_offset(global_transform.basis.inverse * world_offset)

      vel = velocity
      horiz_speed = Vector2.new(vel.x, vel.z).length
      rig.update_bob(horiz_speed, @floor_type == FloorType::GROUND, cfg, dt)
      rig.update_tilt(vel, global_transform.basis * Vector3::RIGHT, cfg, dt)
      rig.update_portal_reorient(cfg, dt)
    end
  end

  def _unhandled_input(event : Godot::InputEvent) : Void
    cfg = active_config
    if is_mouse_look_enabled
      if rig = @camera_rig
        rig.handle_input(event, cfg.mouse_sensitivity, cfg.degrees_per_unit)
      end
    end

    if is_movement_enabled && _action_exists("camera_mode")
      action_name = _action_name("camera_mode")
      if event.is_action_pressed(action_name, false, false)
        toggle_camera_mode
      end
    end

    if is_mouse_look_enabled
      if _action_exists("interact") && event.is_action_pressed(_action_name("interact"), false, false)
        trigger_interact
      elsif (mb = event.as_a?(Godot::InputEventMouseButton)) && mb.is_pressed && mb.get_button_index.value == 1_i64
        if Godot::Input.mouse_mode == Godot::Input::MouseMode::MouseModeCaptured
          trigger_interact
        end
      elsif @is_sitting && ((_action_exists("jump") && event.is_action_pressed(_action_name("jump"), false, false)) || (_action_exists("crouch") && event.is_action_pressed(_action_name("crouch"), false, false)))
        stand
      end
    end
  end

  def _physics_process(delta : Float64) : Void
    dt = delta.to_f32

    if @_teleport_queued
      @_teleport_queued = false
      if (orig = @_teleport_from) && (dest = @_teleport_to)
        teleport_in_relation_to(orig, dest)
      end
      @_teleport_from = nil
      @_teleport_to = nil
    end

    _update_interact_ray

    if @is_sitting || @loading_blocked
      self.velocity = Vector3.zero
      @_phys_pos_prev = global_position
      @_phys_pos_curr = global_position
      _update_movement_state(Vector3.zero)
      return
    end

    @_phys_pos_prev = @_phys_pos_curr
    @_just_jumped = false
    @_pre_move_y_vel = velocity.y

    _update_floor_state

    wish_dir = Vector3.zero
    if is_movement_enabled
      _update_crouch
      wish_dir = _get_wish_dir
    end

    case @floor_type
    when FloorType::GROUND
      _handle_ground_movement(wish_dir, dt)
    when FloorType::RAMP
      _handle_surf_movement(wish_dir, dt)
    when FloorType::NONE
      _handle_air_movement(wish_dir, dt)
    end

    _clamp_velocity
    _move_with_steps(dt)
    _update_floor_state
    _snap_to_stairs_below

    # Landed detection: transitioned from airborne to grounded
    if !@_was_on_floor && @floor_type == FloorType::GROUND
      landed.emit(@_pre_move_y_vel.abs.to_f64)
    end

    @_was_on_floor = (@floor_type == FloorType::GROUND)
    _update_movement_state(wish_dir)
    @_phys_pos_curr = global_position
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  def get_movement_state_name : String
    case @movement_state
    when MovementState::IDLE      then "IDLE"
    when MovementState::WALKING   then "WALKING"
    when MovementState::SPRINTING then "SPRINTING"
    when MovementState::CROUCHING then "CROUCHING"
    when MovementState::FALLING   then "FALLING"
    when MovementState::SURFING   then "SURFING"
    when MovementState::SITTING   then "SITTING"
    else                               "IDLE"
    end
  end

  def get_game_state_name : String
    case @game_state
    when GameState::PLAYING  then "PLAYING"
    when GameState::PAUSED   then "PAUSED"
    when GameState::MENU     then "MENU"
    when GameState::CUTSCENE then "CUTSCENE"
    when GameState::DEAD     then "DEAD"
    else                          "PLAYING"
    end
  end

  def get_floor_type_name : String
    case @floor_type
    when FloorType::NONE   then "NONE"
    when FloorType::GROUND then "GROUND"
    when FloorType::RAMP   then "RAMP"
    else                        "NONE"
    end
  end

  def is_movement_enabled : Bool
    @game_state == GameState::PLAYING && !@is_sitting && !@loading_blocked
  end

  def is_mouse_look_enabled : Bool
    @game_state == GameState::PLAYING && !@loading_blocked
  end

  def set_game_state(new_state : GameState) : Void
    return if new_state == @game_state
    old_state = @game_state
    @game_state = new_state

    if !@pointer.null?
      case @game_state
      when GameState::PLAYING
        Godot::Input.mouse_mode = Godot::Input::MouseMode::MouseModeCaptured
      when GameState::PAUSED, GameState::MENU
        Godot::Input.mouse_mode = Godot::Input::MouseMode::MouseModeVisible
      when GameState::CUTSCENE, GameState::DEAD
        # Leave mouse mode as-is; game code decides
      end
    end

    game_state_changed.emit(old_state, @game_state)
  end

  def set_camera_mode(mode : CameraMode) : Void
    @camera_mode = mode
    cfg = active_config
    if rig = @camera_rig
      rig.apply_mode(mode.value, cfg.third_person_distance)
    end
    if vis = @visual_root
      if !vis.pointer.null?
        vis.visible = (mode == CameraMode::THIRD_PERSON)
      end
    end
    camera_mode_changed.emit(mode)
  end

  def toggle_camera_mode : Void
    if @camera_mode == CameraMode::FIRST_PERSON
      set_camera_mode(CameraMode::THIRD_PERSON)
    else
      set_camera_mode(CameraMode::FIRST_PERSON)
    end
  end

  # ===========================================================================
  # Node Discovery & Collider Setup
  # ===========================================================================

  def _find_camera_rig : SUCCCamera?
    return nil if @pointer.null?
    count = get_child_count
    i = 0_i64
    while i < count
      child = get_child(i)
      if !child.pointer.null?
        if rig = child.as_a?(SUCCCamera)
          return rig
        end
      end
      i += 1
    end
    nil
  end

  def _setup_colliders : Void
    return if @pointer.null?
    # Remove any user-placed CollisionShape3D children to avoid conflicts
    count = get_child_count
    i = count - 1
    while i >= 0
      child = get_child(i)
      if !child.pointer.null? && child.as_a?(Godot::CollisionShape3D)
        remove_child(child)
        child.queue_free
      end
      i -= 1
    end

    stand_col = Godot::CollisionShape3D.create
    stand_col.name = "StandingCollider"
    add_child(stand_col, false, Godot::Node::InternalMode::InternalModeDisabled)
    @standing_collider = stand_col

    crouch_col = Godot::CollisionShape3D.create
    crouch_col.name = "CrouchingCollider"
    crouch_col.disabled = true
    add_child(crouch_col, false, Godot::Node::InternalMode::InternalModeDisabled)
    @crouching_collider = crouch_col

    _rebuild_shapes
  end

  def _rebuild_shapes : Void
    stand_col = @standing_collider
    crouch_col = @crouching_collider
    return unless stand_col && crouch_col
    cfg = active_config

    if @use_cylinders
      stand_shape = Godot::CylinderShape3D.create
      stand_shape.radius = (cfg.width / 2.0_f32).to_f64
      stand_shape.height = cfg.stand_height.to_f64
      stand_col.shape = stand_shape

      crouch_shape = Godot::CylinderShape3D.create
      crouch_shape.radius = (cfg.width / 2.0_f32).to_f64
      crouch_shape.height = cfg.crouch_height.to_f64
      crouch_col.shape = crouch_shape
    else
      stand_shape = Godot::BoxShape3D.create
      stand_shape.size = Vector3.new(cfg.width, cfg.stand_height, cfg.width)
      stand_col.shape = stand_shape

      crouch_shape = Godot::BoxShape3D.create
      crouch_shape.size = Vector3.new(cfg.width, cfg.crouch_height, cfg.width)
      crouch_col.shape = crouch_shape
    end

    stand_col.position = Vector3.new(0.0_f32, cfg.stand_height / 2.0_f32, 0.0_f32)
    crouch_col.position = Vector3.new(0.0_f32, cfg.crouch_height / 2.0_f32, 0.0_f32)
  end

  # ===========================================================================
  # Input Helpers
  # ===========================================================================

  def _sync_input_actions_from_exports : Void
    @input_actions["move_forward"] = @action_move_forward unless @action_move_forward.empty?
    @input_actions["move_backward"] = @action_move_backward unless @action_move_backward.empty?
    @input_actions["move_left"] = @action_move_left unless @action_move_left.empty?
    @input_actions["move_right"] = @action_move_right unless @action_move_right.empty?
    @input_actions["jump"] = @action_jump unless @action_jump.empty?
    @input_actions["crouch"] = @action_crouch unless @action_crouch.empty?
    @input_actions["sprint"] = @action_sprint unless @action_sprint.empty?
    @input_actions["camera_mode"] = @action_camera_mode unless @action_camera_mode.empty?
    @input_actions["interact"] = @action_interact unless @action_interact.empty?
  end

  def _action_name(key : String) : String
    @input_actions[key]? || ""
  end

  def _validate_input_actions : Void
    return if @pointer.null?
    {"move_forward", "move_backward", "move_left", "move_right"}.each do |key|
      act = _action_name(key)
      if act.empty? || !Godot::InputMap.has_action?(act)
        Godot.log_warn("SUCC", "Input action '#{act}' (for '#{key}') is not defined in InputMap. Movement will not work until added in Project Settings > Input Map.")
      end
    end
  end

  def _action_exists(key : String) : Bool
    act = _action_name(key)
    !act.empty? && Godot::InputMap.has_action?(act)
  end

  def _action_pressed(key : String) : Bool
    _action_exists(key) && Godot::Input.is_action_pressed(_action_name(key))
  end

  def _action_just_pressed(key : String) : Bool
    _action_exists(key) && Godot::Input.is_action_just_pressed(_action_name(key))
  end

  def _get_wish_dir : Vector3
    fwd = _action_name("move_forward")
    bwd = _action_name("move_backward")
    lft = _action_name("move_left")
    rgt = _action_name("move_right")

    raw = Vector2.zero
    if _action_exists("move_forward") && _action_exists("move_backward") && _action_exists("move_left") && _action_exists("move_right")
      raw = Godot::Input.get_vector(lft, rgt, fwd, bwd)
    else
      x = (_action_pressed("move_right") ? 1.0_f32 : 0.0_f32) - (_action_pressed("move_left") ? 1.0_f32 : 0.0_f32)
      y = (_action_pressed("move_backward") ? 1.0_f32 : 0.0_f32) - (_action_pressed("move_forward") ? 1.0_f32 : 0.0_f32)
      raw = Vector2.new(x, y)
      raw = raw.normalized if raw.length > 1.0_f32
    end

    dir = global_transform.basis * Vector3.new(raw.x, 0.0_f32, raw.y)
    dir = Vector3.new(dir.x, 0.0_f32, dir.z)
    dir.length > 1.0_f32 ? dir.normalized : dir
  end

  # ===========================================================================
  # Floor & Surf Classification
  # ===========================================================================

  def _update_floor_state : Void
    if is_on_floor
      @floor_type = FloorType::GROUND
      @surf_normal = get_floor_normal
      return
    end

    steep_normal = _get_steepest_contact_normal
    if steep_normal != Vector3.zero
      angle = steep_normal.angle_to(Vector3::UP) * (180.0_f32 / Math::PI.to_f32)
      floor_max_deg = floor_max_angle.to_f32 * (180.0_f32 / Math::PI.to_f32)
      if angle > floor_max_deg && angle <= SURF_MAX_ANGLE
        @floor_type = FloorType::RAMP
        @surf_normal = steep_normal
        return
      end
    end

    @floor_type = FloorType::NONE
    @surf_normal = Vector3::UP
  end

  def _get_steepest_contact_normal : Vector3
    best_normal = Vector3.zero
    best_angle = 0.0_f32
    count = get_slide_collision_count
    i = 0_i64
    while i < count
      col = get_slide_collision(i)
      if !col.pointer.null?
        c_count = col.get_collision_count
        j = 0_i64
        while j < c_count
          n = col.get_normal(j)
          angle = n.angle_to(Vector3::UP)
          if angle > best_angle
            best_angle = angle
            best_normal = n
          end
          j += 1
        end
      end
      i += 1
    end
    best_normal
  end

  # ===========================================================================
  # Crouch
  # ===========================================================================

  def _update_crouch : Void
    cfg = active_config
    # Presets with identical stand/crouch heights (e.g. Quake 1) don't support crouching
    if !@crouch_enabled || (cfg.stand_height - cfg.crouch_height).abs < 0.0001_f32
      _set_crouched(false) if @is_crouched
      return
    end

    wants_crouch = _action_pressed("crouch")
    if wants_crouch && !@is_crouched
      _set_crouched(true)
    elsif !wants_crouch && @is_crouched
      _set_crouched(false) if _can_uncrouch
    end
  end

  def _can_uncrouch : Bool
    return true if @pointer.null?
    stand_col = @standing_collider
    return true unless stand_col && !stand_col.pointer.null?
    shape = stand_col.shape
    return true if shape.pointer.null?

    world = get_world_3d
    return true if world.pointer.null?
    space_state = world.direct_space_state
    return true if space_state.pointer.null?

    cfg = active_config
    height_diff = cfg.stand_height - cfg.crouch_height
    test_pos = global_position + Vector3.new(0.0_f32, cfg.stand_height / 2.0_f32, 0.0_f32)
    if @floor_type == FloorType::NONE
      test_pos = test_pos - Vector3.new(0.0_f32, height_diff, 0.0_f32)
    end

    query = @_shape_query || Godot::PhysicsShapeQueryParameters3D.create
    result = @_shape_result || Godot::PhysicsIntersectShapeResult3D.create
    query.shape = shape
    query.transform = Transform3D.new(global_transform.basis, test_pos)
    query.collision_mask = collision_mask

    if space_state.intersect_shape_into(query, result)
      my_rid = get_rid
      my_id = get_instance_id.to_i64
      hit_count = result.get_intersection_count
      i = 0_i64
      while i < hit_count
        if result.get_collider_rid(i) != my_rid && result.get_collider_id(i) != my_id
          return false
        end
        i += 1
      end
    end
    true
  end

  def _set_crouched(crouching : Bool) : Void
    cfg = active_config
    height_diff = cfg.stand_height - cfg.crouch_height

    # Source-style air crouch: shift body so head stays in place and feet pull up
    if @floor_type == FloorType::NONE && height_diff > 0.0_f32
      if crouching && !@is_crouched
        self.global_position = global_position + Vector3.new(0.0_f32, height_diff, 0.0_f32)
        if cfg.smooth_vertical_step && cfg.crouch_transition_mode == SUCCConfig::CrouchTransitionMode::SMOOTH
          _record_vertical_step_offset(height_diff)
        end
      elsif !crouching && @is_crouched
        self.global_position = global_position - Vector3.new(0.0_f32, height_diff, 0.0_f32)
        if cfg.smooth_vertical_step && cfg.crouch_transition_mode == SUCCConfig::CrouchTransitionMode::SMOOTH
          _record_vertical_step_offset(-height_diff)
        end
      end
    end

    @is_crouched = crouching
    if stand_col = @standing_collider
      stand_col.disabled = crouching
    end
    if crouch_col = @crouching_collider
      crouch_col.disabled = !crouching
    end
    _update_crouch_view(crouching)
  end

  def _update_crouch_view(crouching : Bool) : Void
    rig = @camera_rig
    return unless rig
    cfg = active_config
    target_y = crouching ? cfg.crouch_view_offset : cfg.standing_view_offset

    if cfg.crouch_transition_mode == SUCCConfig::CrouchTransitionMode::SNAP
      @_crouch_tween_active = false
      rig.base_y = target_y
      return
    end

    speed = crouching ? cfg.crouch_smoothing_speed : cfg.uncrouch_smoothing_speed
    @_crouch_tween_duration = (2.0_f32 / speed).clamp(0.05_f32, 0.5_f32)
    @_crouch_tween_elapsed = 0.0_f32
    @_crouch_tween_start_y = rig.base_y
    @_crouch_tween_target_y = target_y
    @_crouch_tween_active = true
  end

  # ===========================================================================
  # Movement Physics (Quake / Source)
  # ===========================================================================

  def _handle_ground_movement(wish_dir : Vector3, delta : Float32) : Void
    cfg = active_config
    wants_jump = false
    if is_movement_enabled
      if cfg.bhop_buffered_jump
        wants_jump = _action_pressed("jump")
      else
        wants_jump = _action_just_pressed("jump")
      end
    end

    # Bhop: skip friction on the frame we jump so speed carries through
    if wants_jump
      vel = velocity
      self.velocity = Vector3.new(vel.x, Math.sqrt(2.0_f32 * cfg.gravity * cfg.jump_height), vel.z)
      @floor_type = FloorType::NONE
      @_just_jumped = true
      jumped.emit
      _air_accelerate(wish_dir, cfg.max_air_speed, cfg.air_acceleration, delta)
      vel = velocity
      self.velocity = Vector3.new(vel.x, vel.y - cfg.gravity * delta, vel.z)
      return
    end

    # Reset vertical velocity before ground friction/acceleration so previous-frame slope Y velocity
    # never re-injects downhill horizontal drift.
    vel_ground = velocity
    self.velocity = Vector3.new(vel_ground.x, 0.0_f32, vel_ground.z)

    _apply_friction(delta)

    wish_speed = cfg.max_speed
    if @is_crouched
      wish_speed *= cfg.crouch_speed_modifier
    elsif @sprint_enabled && is_movement_enabled && _action_pressed("sprint")
      wish_speed *= cfg.sprint_speed_modifier
    end

    _ground_accelerate(wish_dir, wish_speed, cfg.acceleration, delta)

    vel_after = velocity
    horiz_sq = vel_after.x * vel_after.x + vel_after.z * vel_after.z
    if wish_dir.length_squared < 0.0001_f32 && horiz_sq < 0.0025_f32
      self.velocity = Vector3.zero
      return
    end

    # Align horizontal velocity with the walkable floor slope without deflecting downhill
    floor_n = get_floor_normal
    if floor_n != Vector3::UP && floor_n.length_squared > 0.0_f32
      self.velocity = SUCC.slope_tangent_velocity(vel_after, floor_n)
    else
      self.velocity = Vector3.new(vel_after.x, 0.0_f32, vel_after.z)
    end
  end

  def _handle_surf_movement(wish_dir : Vector3, delta : Float32) : Void
    cfg = active_config
    vel = velocity
    self.velocity = Vector3.new(vel.x, vel.y - cfg.gravity * 0.5_f32 * delta, vel.z)
    _air_accelerate(wish_dir, cfg.max_air_speed, cfg.air_acceleration, delta)
    self.velocity = SUCC.clip_velocity(velocity, @surf_normal)
    vel = velocity
    self.velocity = Vector3.new(vel.x, vel.y - cfg.gravity * 0.5_f32 * delta, vel.z)
  end

  def _handle_air_movement(wish_dir : Vector3, delta : Float32) : Void
    cfg = active_config
    vel = velocity
    self.velocity = Vector3.new(vel.x, vel.y - cfg.gravity * 0.5_f32 * delta, vel.z)
    _air_accelerate(wish_dir, cfg.max_air_speed, cfg.air_acceleration, delta)
    vel = velocity
    self.velocity = Vector3.new(vel.x, vel.y - cfg.gravity * 0.5_f32 * delta, vel.z)
  end

  # Quake/Source PM_Accelerate (ground)
  def _ground_accelerate(wish_dir : Vector3, wish_speed : Float32, accel : Float32, delta : Float32) : Void
    return if wish_dir.length_squared < 0.0001_f32
    vel = velocity
    current_speed = Vector3.new(vel.x, 0.0_f32, vel.z).dot(wish_dir)
    add_speed = wish_speed - current_speed
    return if add_speed <= 0.0_f32

    accel_speed = accel * wish_speed * delta
    accel_speed = add_speed if accel_speed > add_speed

    self.velocity = Vector3.new(
      vel.x + wish_dir.x * accel_speed,
      vel.y,
      vel.z + wish_dir.z * accel_speed
    )
  end

  # Quake/Source PM_AirAccelerate: wish_speed is capped to max_air_speed (~30 u/s)
  # before computing add_speed, enabling airstrafing when wish_dir is nearly perpendicular.
  def _air_accelerate(wish_dir : Vector3, wish_speed : Float32, accel : Float32, delta : Float32) : Void
    return if wish_dir.length_squared < 0.0001_f32
    cfg = active_config
    vel = velocity
    horiz_vel = Vector3.new(vel.x, 0.0_f32, vel.z)
    current_speed = horiz_vel.dot(wish_dir)

    add_speed = wish_speed - current_speed
    return if add_speed <= 0.0_f32

    accel_speed = accel * cfg.max_speed * delta
    accel_speed = add_speed if accel_speed > add_speed

    self.velocity = Vector3.new(
      vel.x + wish_dir.x * accel_speed,
      vel.y,
      vel.z + wish_dir.z * accel_speed
    )
  end

  # Quake/Source PM_Friction
  def _apply_friction(delta : Float32) : Void
    cfg = active_config
    vel = velocity
    horiz = Vector2.new(vel.x, vel.z)
    speed = horiz.length
    if speed < 0.001_f32
      self.velocity = Vector3.zero
      return
    end

    control = speed < cfg.stop_speed ? cfg.stop_speed : speed
    drop = control * cfg.friction * delta
    new_speed = speed - drop
    new_speed = 0.0_f32 if new_speed < 0.0_f32
    new_speed /= speed

    self.velocity = Vector3.new(vel.x * new_speed, vel.y * new_speed, vel.z * new_speed)
  end

  # Projects a horizontal velocity vector `(horiz_vel.x, 0, horiz_vel.z)` onto a walkable floor plane
  # with normal `floor_n` (`v . floor_n == 0`) while preserving horizontal direction without downhill drift.
  def self.slope_tangent_velocity(horiz_vel : Vector3, floor_n : Vector3) : Vector3
    return Vector3.new(horiz_vel.x, 0.0_f32, horiz_vel.z) if floor_n.y <= 0.01_f32
    vy = -(horiz_vel.x * floor_n.x + horiz_vel.z * floor_n.z)
    Vector3.new(horiz_vel.x * floor_n.y, vy, horiz_vel.z * floor_n.y)
  end

  # Quake PM_ClipVelocity: project velocity onto surface plane (overbounce = 1.0)
  def self.clip_velocity(vel : Vector3, normal : Vector3) : Vector3
    backoff = vel.dot(normal)
    vel - normal * backoff
  end

  def _clip_velocity(vel : Vector3, normal : Vector3) : Vector3
    SUCC.clip_velocity(vel, normal)
  end

  # Source CheckVelocity: axial clamp on each component independently (sv_maxvelocity)
  def _clamp_velocity : Void
    cfg = active_config
    return unless cfg.enforce_max_velocity
    max_v = cfg.max_velocity
    vel = velocity
    self.velocity = Vector3.new(
      vel.x.clamp(-max_v, max_v),
      vel.y.clamp(-max_v, max_v),
      vel.z.clamp(-max_v, max_v)
    )
  end

  # ===========================================================================
  # Stair Stepping & View Smoothing
  # ===========================================================================

  # Records a discrete vertical step `delta_y` (`new_y - old_y`) into `@_step_Lists_offset` and shifts
  # `@_phys_pos_prev.y` by the absorbed amount so manual physics interpolation never double-subtracts the step.
  def _record_vertical_step_offset(delta_y : Float32) : Void
    cfg = active_config
    max_off = Math.max(0.25_f32, cfg.step_height * 1.35_f32)
    old_off = @_step_Lists_offset
    new_off = (old_off - delta_y).clamp(-max_off, max_off)
    absorbed_y = old_off - new_off
    @_step_Lists_offset = new_off
    @_phys_pos_prev = Vector3.new(@_phys_pos_prev.x, @_phys_pos_prev.y + absorbed_y, @_phys_pos_prev.z)
    if rig = @camera_rig
      rig.set_step_offset(@_step_Lists_offset)
    end
  end

  def _move_with_steps(delta : Float32) : Void
    cfg = active_config
    step_h = cfg.step_height
    if step_h <= 0.0_f32
      move_and_slide
      return
    end

    if @floor_type == FloorType::GROUND
      vel = velocity
      horiz_vel = Vector3.new(vel.x, 0.0_f32, vel.z)
      if horiz_vel.length_squared > 0.0001_f32 && _try_step_up(horiz_vel * delta, step_h)
        # `_try_step_up` already advanced horizontally by `horiz_travel` onto the step surface.
        # Perform a zero-horizontal floor-registration slide so Godot updates `is_on_floor` without double-moving.
        saved_vel = velocity
        self.velocity = Vector3.new(0.0_f32, -0.05_f32, 0.0_f32)
        move_and_slide
        self.velocity = saved_vel
        return
      end
      move_and_slide
    elsif @floor_type == FloorType::NONE
      vel = velocity
      horiz_vel = Vector3.new(vel.x, 0.0_f32, vel.z)
      if horiz_vel.length_squared > 0.0001_f32 && vel.y <= 0.0_f32
        if _try_air_step(horiz_vel * delta, step_h)
          saved_vel = velocity
          self.velocity = Vector3.new(0.0_f32, -0.05_f32, 0.0_f32)
          move_and_slide
          self.velocity = saved_vel
          return
        end
      end
      move_and_slide
    else
      move_and_slide
    end
  end

  def _try_step_up(horiz_motion : Vector3, step_h : Float32) : Bool
    return false if @pointer.null?
    up_col = @_up_collision || Godot::KinematicCollision3D.create
    fwd_col = @_fwd_collision || Godot::KinematicCollision3D.create
    down_col = @_down_collision || Godot::KinematicCollision3D.create

    # Only step up if horizontal movement is blocked at current height by a non-walkable step/riser
    return false unless test_move(global_transform, horiz_motion, fwd_col)
    if fwd_col.get_collision_count > 0
      has_steep_blocker = false
      c_cnt = fwd_col.get_collision_count
      ci = 0_i64
      while ci < c_cnt
        n = fwd_col.get_normal(ci)
        if n.angle_to(Vector3::UP) > floor_max_angle.to_f32
          has_steep_blocker = true
          break
        end
        ci += 1
      end
      return false unless has_steep_blocker
    end

    from_pos = global_position

    # 1. Sweep up by step_h (using actual travel if ceiling is lower)
    up_vec = Vector3.new(0.0_f32, step_h, 0.0_f32)
    raised_pos = from_pos + up_vec
    if test_move(global_transform, up_vec, up_col)
      up_travel = up_col.get_travel
      return false if up_travel.y < 0.01_f32
      raised_pos = from_pos + up_travel
    end

    # 2. Sweep forward at the raised height (sliding along side walls/handrails if blocked laterally)
    raised_xf = Transform3D.new(global_transform.basis, raised_pos)
    horiz_travel = horiz_motion
    if test_move(raised_xf, horiz_motion, fwd_col)
      first_travel = fwd_col.get_travel
      rem = horiz_motion - first_travel
      if fwd_col.get_collision_count > 0
        wall_n = fwd_col.get_normal(0_i64)
        wall_n_xz = Vector3.new(wall_n.x, 0.0_f32, wall_n.z)
        if wall_n_xz.length_squared > 1e-4_f32
          wall_n_xz = wall_n_xz.normalized
          slide_rem = SUCC.clip_velocity(rem, wall_n_xz)
          slide_rem = Vector3.new(slide_rem.x, 0.0_f32, slide_rem.z)
          if slide_rem.length_squared > 1e-6_f32
            mid_xf = Transform3D.new(global_transform.basis, raised_pos + first_travel)
            if test_move(mid_xf, slide_rem, fwd_col)
              horiz_travel = first_travel + fwd_col.get_travel
            else
              horiz_travel = first_travel + slide_rem
            end
          else
            horiz_travel = first_travel
          end
        else
          horiz_travel = first_travel
        end
      else
        horiz_travel = first_travel
      end
      return false if Vector2.new(horiz_travel.x, horiz_travel.z).length < 0.001_f32
    end

    # 3. Sweep down to land on the step surface (up to step_h)
    step_xf = Transform3D.new(global_transform.basis, raised_pos + horiz_travel)
    down_vec = Vector3.new(0.0_f32, -step_h, 0.0_f32)
    return false unless test_move(step_xf, down_vec, down_col)

    step_pos = step_xf.origin + down_col.get_travel
    step_diff = step_pos.y - from_pos.y
    return false if step_diff <= 0.01_f32 || step_diff > step_h + 0.01_f32

    # Verify surface normal is a walkable floor (not a steep ramp)
    has_normal = down_col.get_collision_count > 0
    hit_normal = has_normal ? down_col.get_normal(0_i64) : Vector3::UP
    world = get_world_3d
    if !world.pointer.null?
      space_state = world.direct_space_state
      if !space_state.pointer.null?
        ray_origin = step_pos + Vector3.new(0.0_f32, step_h + 0.01_f32, 0.0_f32)
        ray_end = ray_origin + Vector3.new(0.0_f32, -(step_h + 0.05_f32), 0.0_f32)
        r_query = @_ray_query || Godot.create(Godot::PhysicsRayQueryParameters3D)
        r_result = @_ray_result || Godot::PhysicsIntersectRayResult3D.create
        r_query.from = ray_origin
        r_query.to = ray_end
        r_query.collision_mask = collision_mask
        if space_state.intersect_ray_into(r_query, r_result)
          if r_result.collider_rid != get_rid && r_result.collider_id != get_instance_id.to_i64
            hit_normal = r_result.normal
            has_normal = true
          end
        end
      end
    end

    return false unless has_normal
    return false if hit_normal.angle_to(Vector3::UP) > floor_max_angle.to_f32

    # Commit the step: teleport onto the step surface
    self.global_position = step_pos
    vel = velocity
    self.velocity = SUCC.slope_tangent_velocity(Vector3.new(vel.x, 0.0_f32, vel.z), hit_normal)
    @floor_type = FloorType::GROUND
    @surf_normal = hit_normal
    if active_config.smooth_vertical_step
      _record_vertical_step_offset(step_diff)
    end
    true
  end

  def _try_air_step(horiz_motion : Vector3, step_h : Float32) : Bool
    return false if @pointer.null?
    up_col = @_up_collision || Godot::KinematicCollision3D.create
    fwd_col = @_fwd_collision || Godot::KinematicCollision3D.create
    down_col = @_down_collision || Godot::KinematicCollision3D.create

    return false unless test_move(global_transform, horiz_motion, fwd_col)
    if fwd_col.get_collision_count > 0
      has_steep_blocker = false
      c_cnt = fwd_col.get_collision_count
      ci = 0_i64
      while ci < c_cnt
        n = fwd_col.get_normal(ci)
        if n.angle_to(Vector3::UP) > floor_max_angle.to_f32
          has_steep_blocker = true
          break
        end
        ci += 1
      end
      return false unless has_steep_blocker
    end

    from_pos = global_position

    # 1. Sweep up by step_h
    up_vec = Vector3.new(0.0_f32, step_h, 0.0_f32)
    raised_pos = from_pos + up_vec
    if test_move(global_transform, up_vec, up_col)
      up_travel = up_col.get_travel
      return false if up_travel.y < 0.01_f32
      raised_pos = from_pos + up_travel
    end

    # 2. Sweep forward at the raised height
    raised_xf = Transform3D.new(global_transform.basis, raised_pos)
    horiz_travel = horiz_motion
    if test_move(raised_xf, horiz_motion, fwd_col)
      horiz_travel = fwd_col.get_travel
      return false if Vector2.new(horiz_travel.x, horiz_travel.z).length < 0.001_f32
    end

    # 3. Sweep down to find the ledge surface
    step_xf = Transform3D.new(global_transform.basis, raised_pos + horiz_travel)
    down_vec = Vector3.new(0.0_f32, -step_h, 0.0_f32)
    return false unless test_move(step_xf, down_vec, down_col)

    step_pos = step_xf.origin + down_col.get_travel
    step_diff = step_pos.y - from_pos.y
    return false if step_diff <= 0.01_f32 || step_diff > step_h + 0.01_f32
    return false if down_col.get_collision_count <= 0

    hit_normal = down_col.get_normal(0_i64)
    return false if hit_normal.angle_to(Vector3::UP) > floor_max_angle.to_f32

    self.global_position = step_pos
    vel = velocity
    self.velocity = SUCC.slope_tangent_velocity(Vector3.new(vel.x, 0.0_f32, vel.z), hit_normal)
    @floor_type = FloorType::GROUND
    @surf_normal = hit_normal
    if active_config.smooth_vertical_step
      _record_vertical_step_offset(step_diff)
    end
    true
  end

  def _snap_to_stairs_below : Void
    return if @pointer.null?
    return if @floor_type != FloorType::NONE || !@_was_on_floor || @_just_jumped
    return if velocity.y > 0.0_f32

    cfg = active_config
    step_h = cfg.step_height
    return if step_h <= 0.0_f32

    down_col = @_down_collision || Godot::KinematicCollision3D.create
    down_vec = Vector3.new(0.0_f32, -step_h, 0.0_f32)
    return unless test_move(global_transform, down_vec, down_col)

    travel = down_col.get_travel
    drop = -travel.y
    return if drop <= 0.001_f32 || drop > step_h + 0.01_f32
    return if down_col.get_collision_count <= 0

    hit_normal = down_col.get_normal(0_i64)
    return if hit_normal.angle_to(Vector3::UP) > floor_max_angle.to_f32

    self.global_position = global_position + travel
    vel = velocity
    self.velocity = SUCC.slope_tangent_velocity(Vector3.new(vel.x, 0.0_f32, vel.z), hit_normal)
    @floor_type = FloorType::GROUND
    @surf_normal = hit_normal
    if cfg.smooth_vertical_step
      _record_vertical_step_offset(-drop)
    end
  end

  def _smooth_camera_step(delta : Float32) : Void
    rig = @camera_rig
    return unless rig
    cfg = active_config
    if !cfg.smooth_vertical_step || @_step_Lists_offset.abs < 0.0005_f32
      @_step_Lists_offset = 0.0_f32
      rig.set_step_offset(0.0_f32)
      return
    end
    alpha = (1.0_f32 - Math.exp(-cfg.step_smoothing_speed * delta)).clamp(0.0_f32, 1.0_f32)
    decayed = Math.lerp(@_step_Lists_offset, 0.0_f32, alpha)
    # Add a gentle minimum linear convergence so residual sub-centimeter offset finishes smoothly
    @_step_Lists_offset = Math.move_toward(decayed, 0.0_f32, delta * 0.15_f32)
    rig.set_step_offset(@_step_Lists_offset)
  end

  # ===========================================================================
  # Movement State Machine
  # ===========================================================================

  def _update_movement_state(wish_dir : Vector3) : Void
    new_state = @movement_state
    if @is_sitting
      new_state = MovementState::SITTING
    else
      case @floor_type
      when FloorType::RAMP
        new_state = MovementState::SURFING
      when FloorType::NONE
        new_state = MovementState::FALLING
      when FloorType::GROUND
        vel = velocity
        horiz_speed = Vector2.new(vel.x, vel.z).length
        if @is_crouched
          new_state = MovementState::CROUCHING
        elsif horiz_speed < 0.1_f32 && wish_dir.length_squared < 0.01_f32
          new_state = MovementState::IDLE
        elsif @sprint_enabled && is_movement_enabled && _action_pressed("sprint")
          new_state = MovementState::SPRINTING
        else
          new_state = MovementState::WALKING
        end
      end
    end

    if new_state != @movement_state
      old_state = @movement_state
      @movement_state = new_state
      movement_state_changed.emit(old_state, @movement_state)
    end
  end

  # ===========================================================================
  # Interact Ray, Sit State & Relative Portal Teleportation
  # ===========================================================================

  def _setup_interact_ray : Void
    return if @pointer.null?
    parent_node : Godot::Node3D = self
    if rig = @camera_rig
      if cam = rig.camera || rig._find_camera(rig)
        parent_node = cam
      else
        parent_node = rig
      end
    end

    existing = parent_node.get_node_or_null("InteractRay").as?(Godot::RayCast3D)
    ray = existing || Godot::RayCast3D.create
    if !existing
      ray.name = "InteractRay"
      parent_node.add_child(ray, false, Godot::Node::InternalMode::InternalModeDisabled)
    end
    ray.enabled = true
    ray.target_position = Vector3.new(0.0_f32, 0.0_f32, -@interact_distance)
    ray.add_exception(self)
    @interact_ray = ray
  end

  # Returns the `Godot::Node` currently hit by the player's interaction raycast (or `nil`).
  def get_interact_collider : Godot::Node?
    return nil if @pointer.null?
    if ray = @interact_ray
      if !ray.pointer.null?
        ray.target_position = Vector3.new(0.0_f32, 0.0_f32, -@interact_distance)
        if ray.is_colliding
          col_obj = ray.get_collider
          if !col_obj.pointer.null?
            return col_obj.as_a?(Godot::Node)
          end
        end
      end
    end
    nil
  end

  # Returns the world-space collision point of the player's interaction raycast (or `nil`).
  def get_interact_hit_point : Vector3?
    return nil if @pointer.null?
    if ray = @interact_ray
      if !ray.pointer.null? && ray.is_colliding
        return ray.get_collision_point
      end
    end
    nil
  end

  # Resolves a hit collider (or its ancestor) that responds to `interact`.
  def _resolve_interactable(node : Godot::Node?) : Godot::Node?
    curr = node
    while curr && !curr.pointer.null?
      return curr if curr.has_method("interact")
      curr = curr.get_parent
    end
    nil
  end

  def _update_interact_ray : Void
    hit_node = _resolve_interactable(get_interact_collider)
    if active = hit_node
      if !active.pointer.null?
        if hit_pt = get_interact_hit_point
          active.set_meta("last_interact_hit_pos", hit_pt)
        end
      end
    end
    prev = @focused_interactable

    if prev.try(&.pointer) != hit_node.try(&.pointer)
      if old_node = prev
        if !old_node.pointer.null? && old_node.has_method("unfocus")
          old_node.set_meta("last_interactor", self.pointer)
          old_node.call("unfocus")
        end
      end
      @focused_interactable = hit_node
      if new_node = hit_node
        if !new_node.pointer.null? && new_node.has_method("focus")
          new_node.set_meta("last_interactor", self.pointer)
          new_node.call("focus")
        end
      end
    end
  end

  # Invokes `interact` on the currently focused `Interactable` node (or stands up if currently sitting and looking at nothing).
  def trigger_interact : Bool
    if @focused_interactable.nil? || @focused_interactable.try(&.pointer.null?)
      _update_interact_ray
    end
    if target = @focused_interactable
      if !target.pointer.null? && target.has_method("interact")
        if hit_pt = get_interact_hit_point
          target.set_meta("last_interact_hit_pos", hit_pt)
        end
        target.set_meta("last_interactor", self.pointer)
        target.call("interact")
        interacted.emit(target)
        return true
      end
    end
    if @is_sitting
      stand
      return true
    end
    false
  end

  # Puts the player into the **Sit State** at `seat_global_transform`:
  # - Disables movement (`is_movement_enabled == false`) while keeping mouse look active (`is_mouse_look_enabled == true`).
  # - Positions the player so the camera sits at `seat_global_transform.origin` facing `seat_global_transform.basis`.
  # - Constrains horizontal yaw to `[-yaw_right_deg, +yaw_left_deg]` and vertical pitch to `[pitch_down_deg, pitch_up_deg]`.
  def sit(
    seat_global_transform : Transform3D,
    yaw_left_deg : Float32 = 80.0_f32,
    yaw_right_deg : Float32 = 80.0_f32,
    pitch_down_deg : Float32 = -60.0_f32,
    pitch_up_deg : Float32 = 60.0_f32,
    chair_node : Godot::Node3D? = nil
  ) : Void
    if !@is_sitting
      @pre_sit_transform = global_transform
    end

    @is_sitting = true
    @active_chair = chair_node
    self.velocity = Vector3.zero

    cfg = active_config
    view_h = @is_crouched ? cfg.crouch_view_offset : cfg.standing_view_offset

    # Extract horizontal forward direction from seat_global_transform
    fwd = seat_global_transform.basis * Vector3.new(0.0_f32, 0.0_f32, -1.0_f32)
    horiz_fwd = Vector3.new(fwd.x, 0.0_f32, fwd.z)
    yaw_angle = if horiz_fwd.length_squared > 1e-5_f32
                  Math.atan2(-horiz_fwd.x, -horiz_fwd.z)
                else
                  rotation.y
                end

    self.global_position = seat_global_transform.origin - Vector3.new(0.0_f32, view_h, 0.0_f32)
    self.rotation = Vector3.new(0.0_f32, yaw_angle, 0.0_f32)
    @_phys_pos_prev = global_position
    @_phys_pos_curr = global_position

    if rig = @camera_rig
      rig.yaw_constrained = true
      rig.accumulated_sit_yaw = 0.0_f32
      rig.max_yaw_left_deg = yaw_left_deg
      rig.max_yaw_right_deg = yaw_right_deg
      rig.min_pitch_deg = pitch_down_deg
      rig.max_pitch_deg = pitch_up_deg
      rig.rotation = Vector3.zero
    end

    _update_movement_state(Vector3.zero)
    if ch = chair_node
      sat_down.emit(ch)
    else
      sat_down.emit(self)
    end
  end

  # Exits the **Sit State**, restores the player's pre-sit position, and removes camera rotation constraints.
  def stand : Void
    return unless @is_sitting
    @is_sitting = false
    @active_chair = nil

    if rig = @camera_rig
      rig.yaw_constrained = false
      rig.accumulated_sit_yaw = 0.0_f32
    end

    self.global_position = @pre_sit_transform.origin
    @_phys_pos_prev = global_position
    @_phys_pos_curr = global_position
    _update_movement_state(Vector3.zero)
    stood_up.emit
  end

  # Toggles between sitting at `seat_global_transform` and standing up.
  def sit_toggle(
    seat_global_transform : Transform3D,
    yaw_left_deg : Float32 = 80.0_f32,
    yaw_right_deg : Float32 = 80.0_f32,
    pitch_down_deg : Float32 = -60.0_f32,
    pitch_up_deg : Float32 = 60.0_f32,
    chair_node : Godot::Node3D? = nil
  ) : Bool
    if @is_sitting
      stand
      false
    else
      sit(seat_global_transform, yaw_left_deg, yaw_right_deg, pitch_down_deg, pitch_up_deg, chair_node)
      true
    end
  end

  # Computes a singularity-free upright target yaw and pitch from an orthonormalized exit camera basis:
  # - Uses the sagittal horizon vector `v_sag = u_y * f_xz - f_y * u_xz` so straight-down (-90°), straight-up (+90°),
  #   and slightly over-pitched transitions through downward/upward portals never gimbal-lock or flip yaw 180°.
  # - When `horizon_pitch_assist` is true and `portal_tilt_cos < 0.995` (angled portal transition), clamps target pitch
  #   to `±max_exit_pitch_deg` while `SUCCCamera` smoothly slerps from the exact 3D exit orientation at `t = 0`.
  def self.compute_portal_exit_yaw_and_pitch(
    exit_basis_in : Basis,
    fallback_yaw : Float32,
    portal_tilt_cos : Float32 = 1.0_f32,
    horizon_pitch_assist : Bool = true,
    max_exit_pitch_deg : Float32 = 55.0_f32,
  ) : Tuple(Float32, Float32)
    b = exit_basis_in.orthonormalized
    f_exit = (b * Vector3.new(0.0_f32, 0.0_f32, -1.0_f32)).normalized
    u_exit = (b * Vector3.new(0.0_f32, 1.0_f32, 0.0_f32)).normalized
    r_exit = (b * Vector3.new(1.0_f32, 0.0_f32, 0.0_f32)).normalized

    f_xz = Vector3.new(f_exit.x, 0.0_f32, f_exit.z)
    u_xz = Vector3.new(u_exit.x, 0.0_f32, u_exit.z)
    v_sag = (f_xz * u_exit.y) - (u_xz * f_exit.y)

    target_yaw = if v_sag.length_squared > 1e-5_f32
                   Math.atan2(-v_sag.x, -v_sag.z)
                 else
                   r_horiz = r_exit.cross(Vector3::UP)
                   r_horiz_xz = Vector3.new(r_horiz.x, 0.0_f32, r_horiz.z)
                   if r_horiz_xz.length_squared > 1e-5_f32
                     Math.atan2(-r_horiz_xz.x, -r_horiz_xz.z)
                   elsif f_xz.length_squared > 1e-5_f32
                     Math.atan2(-f_xz.x, -f_xz.z)
                   else
                     fallback_yaw
                   end
                 end

    raw_pitch = Math.asin(f_exit.y.clamp(-1.0_f32, 1.0_f32))
    deg_to_rad = Math::PI.to_f32 / 180.0_f32
    hard_limit = 89.0_f32 * deg_to_rad
    target_pitch = if horizon_pitch_assist && portal_tilt_cos < 0.995_f32
                     assist_limit = max_exit_pitch_deg.clamp(15.0_f32, 89.0_f32) * deg_to_rad
                     raw_pitch.clamp(-assist_limit, assist_limit)
                   else
                     raw_pitch.clamp(-hard_limit, hard_limit)
                   end

    {target_yaw, target_pitch}
  end

  # Applies an upright target `(target_yaw, target_pitch)` to `SUCC` and `SUCCCamera` while preserving
  # 100% 3D rotational (`exit_cam_basis`) and positional (`desired_eye_world_pos`) camera continuity at `t = 0`,
  # smoothly decaying the residual roll/pitch quaternion and eye-to-hull position offset back to upright.
  def apply_portal_camera_transition(
    exit_cam_basis : Basis,
    desired_eye_world_pos : Vector3,
    target_yaw : Float32,
    target_pitch : Float32,
  ) : Void
    cfg = active_config
    view_h = @is_crouched ? cfg.crouch_view_offset : cfg.standing_view_offset

    self.rotation = Vector3.new(0.0_f32, target_yaw, 0.0_f32)
    @_step_Lists_offset = 0.0_f32

    if rig = (@camera_rig || _find_camera_rig)
      @camera_rig = rig
      if rig.base_y.abs <= 1e-5_f32
        rig.base_y = view_h
      end
      rig.set_step_offset(0.0_f32)
      rig.set_physics_offset(Vector3.zero)
      rig.rotation = Vector3.new(target_pitch, 0.0_f32, 0.0_f32)

      if cfg.portal_smooth_reorient
        b_rig = (Basis.from_axis_angle(Vector3::UP, target_yaw) * Basis.from_axis_angle(Vector3::RIGHT, target_pitch)).orthonormalized
        b_exit = exit_cam_basis.orthonormalized
        b_rel = (b_rig.transposed * b_exit).orthonormalized
        rot_offset = SUCCCamera.basis_to_quaternion(b_rel)

        upright_eye_pos = global_position + Vector3.new(0.0_f32, view_h, 0.0_f32)
        world_eye_delta = desired_eye_world_pos - upright_eye_pos
        if world_eye_delta.length > 1.25_f32
          world_eye_delta = world_eye_delta.normalized * 1.25_f32
        end
        local_pos_offset = Basis.from_axis_angle(Vector3::UP, -target_yaw) * world_eye_delta
        rig.set_portal_transition_offsets(rot_offset, local_pos_offset)
      else
        rig.clear_portal_transition_offsets
      end
    end
  end

  # Queues a relative non-Euclidean portal teleport from `origin_node` to `target_node` on the next physics tick.
  def queue_teleport_in_relation_to(origin_node : Godot::Node3D, target_node : Godot::Node3D) : Void
    @_teleport_from = origin_node
    @_teleport_to = target_node
    @_teleport_queued = true
  end

  # Immediately teleports the player from `origin_node`'s local space to `target_node`'s local space,
  # preserving eye-exact 3D camera continuity, smooth horizon reorientation, and velocity vector.
  def teleport_in_relation_to(origin_node : Godot::Node3D, target_node : Godot::Node3D) : Void
    return if @pointer.null? || origin_node.pointer.null? || target_node.pointer.null?
    orig_xf = origin_node.global_transform
    dest_xf = target_node.global_transform
    cfg = active_config
    view_h = @is_crouched ? cfg.crouch_view_offset : cfg.standing_view_offset

    rig = @camera_rig
    enter_cam_xf = if r = rig
                     r.effective_camera_global_transform
                   else
                     Transform3D.new(global_transform.basis, global_position + Vector3.new(0.0_f32, view_h, 0.0_f32))
                   end

    rel_cam_xf = orig_xf.affine_inverse * enter_cam_xf
    exit_cam_xf = dest_xf * rel_cam_xf
    exit_cam_basis = exit_cam_xf.basis.orthonormalized

    orig_up = (orig_xf.basis * Vector3::UP).normalized
    dest_up = (dest_xf.basis * Vector3::UP).normalized
    tilt_cos = Math.min(orig_up.dot(dest_up), Math.min(orig_up.dot(Vector3::UP), dest_up.dot(Vector3::UP)))

    target_yaw, target_pitch = SUCC.compute_portal_exit_yaw_and_pitch(
      exit_cam_basis,
      rotation.y,
      portal_tilt_cos: tilt_cos,
      horizon_pitch_assist: cfg.portal_horizon_pitch_assist,
      max_exit_pitch_deg: cfg.portal_max_exit_pitch_deg
    )

    desired_eye_pos = exit_cam_xf.origin
    self.global_position = desired_eye_pos - Vector3.new(0.0_f32, view_h, 0.0_f32)
    @_phys_pos_prev = global_position
    @_phys_pos_curr = global_position

    apply_portal_camera_transition(exit_cam_basis, desired_eye_pos, target_yaw, target_pitch)

    # Rotate velocity vector by the portal delta basis
    rot_delta = dest_xf.basis.orthonormalized * orig_xf.basis.orthonormalized.transposed
    self.velocity = rot_delta * velocity
  end
end
