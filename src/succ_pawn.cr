# Lightweight networked player representation for SUCC.
#
# Receives synced state via MultiplayerSynchronizer and interpolates visuals.
# Does not run movement physics, input, or camera logic.
#
# Original GDScript implementation by Mark Arneman (bearlikelion) & Nerdiful:
# https://github.com/bearlikelion/SUCC
node SUCCPawn < CharacterBody3D do
  @[Export]
  property interpolate : Bool = true

  @[Export]
  property interpolation_speed : Float32 = 20.0_f32

  @[Export]
  property synced_position : Vector3 = Vector3.zero

  @[Export]
  property synced_yaw : Float32 = 0.0_f32

  @[Export]
  property synced_pitch : Float32 = 0.0_f32

  @[Export]
  property synced_velocity : Vector3 = Vector3.zero

  @[Export]
  property synced_movement_state : Int64 = 0_i64

  @[Export]
  property synced_game_state : Int64 = 0_i64

  @[Export]
  property synced_crouched : Bool = false

  onready camera_pivot : Godot::Node3D? = "CameraPivot"

  def _lerp_angle(from : Float32, to : Float32, weight : Float32) : Float32
    tau = (Math::PI * 2.0).to_f32
    diff = (to - from) % tau
    shortest = ((2.0_f32 * diff) % tau) - diff
    from + shortest * weight
  end

  def _physics_process(delta : Float64) : Void
    dt = delta.to_f32
    t = (dt * @interpolation_speed).clamp(0.0_f32, 1.0_f32)
    if @interpolate
      self.global_position = global_position.lerp(@synced_position, t)
      rot = rotation
      self.rotation = Vector3.new(rot.x, _lerp_angle(rot.y, @synced_yaw, t), rot.z)
      if pivot = @camera_pivot
        if !pivot.pointer.null?
          p_rot = pivot.rotation
          pivot.rotation = Vector3.new(_lerp_angle(p_rot.x, @synced_pitch, t), p_rot.y, p_rot.z)
        end
      end
    else
      self.global_position = @synced_position
      rot = rotation
      self.rotation = Vector3.new(rot.x, @synced_yaw, rot.z)
      if pivot = @camera_pivot
        if !pivot.pointer.null?
          p_rot = pivot.rotation
          pivot.rotation = Vector3.new(@synced_pitch, p_rot.y, p_rot.z)
        end
      end
    end
    self.velocity = @synced_velocity
  end
end
