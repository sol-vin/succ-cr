require "spec"
require "../src/main"

describe SUCCConfig do
  it "registers with Godot ClassRegistry as a tool Resource" do
    entry = Godot::ClassRegistry.find("SUCCConfig")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("Resource")
    entry.not_nil!.is_tool.should be_true
  end

  it "declares all movement, collider, step, crouch, camera, and mouse properties" do
    entry = Godot::ClassRegistry.find("SUCCConfig").not_nil!
    props = entry.properties.map(&.name)
    props.should contain("gravity")
    props.should contain("jump_height")
    props.should contain("bhop_buffered_jump")
    props.should contain("acceleration")
    props.should contain("friction")
    props.should contain("stop_speed")
    props.should contain("max_speed")
    props.should contain("air_acceleration")
    props.should contain("max_air_speed")
    props.should contain("max_velocity")
    props.should contain("enforce_max_velocity")
    props.should contain("crouch_speed_modifier")
    props.should contain("sprint_speed_modifier")
    props.should contain("stand_height")
    props.should contain("crouch_height")
    props.should contain("width")
    props.should contain("step_height")
    props.should contain("standing_view_offset")
    props.should contain("crouch_view_offset")
    props.should contain("crouch_transition_mode")
    props.should contain("third_person_distance")
    props.should contain("smooth_vertical_step")
    props.should contain("bob_amount")
    props.should contain("tilt_angle")
    props.should contain("mouse_sensitivity")
  end

  it "encodes export suffix hints on properties" do
    entry = Godot::ClassRegistry.find("SUCCConfig").not_nil!
    height_prop = entry.properties.find { |p| p.name == "stand_height" }
    height_prop.should_not be_nil
    height_prop.not_nil!.hint_string.should contain("suffix:m")

    sprint_prop = entry.properties.find { |p| p.name == "sprint_speed_modifier" }
    sprint_prop.should_not be_nil
    sprint_prop.not_nil!.hint_string.should contain("suffix:×")
  end

  it "converts Source/Quake units to Godot meters" do
    SUCCConfig.source_units(39.37_f32).should be_close(1.0_f32, 0.001_f32)
    SUCCConfig.quake_units(39.37_f32).should be_close(1.0_f32, 0.001_f32)
    SUCCConfig.to_source_units(1.0_f32).should be_close(39.37_f32, 0.001_f32)
  end

  it "provides engine presets matching Default, Quake, Quake 2, GoldSrc, and Source" do
    def_cfg = SUCCConfig.default_preset
    def_cfg.bhop_buffered_jump.should be_true
    def_cfg.crouch_transition_mode.should eq(SUCCConfig::CrouchTransitionMode::SMOOTH)

    q1 = SUCCConfig.quake_preset
    q1.bhop_buffered_jump.should be_false
    q1.friction.should eq(6.0_f32)
    q1.enforce_max_velocity.should be_true
    q1.crouch_transition_mode.should eq(SUCCConfig::CrouchTransitionMode::SNAP)

    q2 = SUCCConfig.quake2_preset
    q2.air_acceleration.should eq(1.0_f32)
    q2.max_speed.should be_close(7.62_f32, 0.01_f32)
    q2.crouch_transition_mode.should eq(SUCCConfig::CrouchTransitionMode::SNAP)

    gs = SUCCConfig.goldsrc_preset
    gs.friction.should eq(4.0_f32)
    gs.crouch_transition_mode.should eq(SUCCConfig::CrouchTransitionMode::SNAP)

    src = SUCCConfig.source_preset
    src.gravity.should be_close(15.24_f32, 0.01_f32)
    src.crouch_transition_mode.should eq(SUCCConfig::CrouchTransitionMode::SMOOTH)
    src.max_speed.should be_close(4.826_f32, 0.01_f32)
    src.sprint_speed_modifier.should be_close(1.684_f32, 0.01_f32)
  end
end

describe SUCCCamera do
  it "registers with Godot ClassRegistry as SpringArm3D" do
    entry = Godot::ClassRegistry.find("SUCCCamera")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("SpringArm3D")
  end

  it "declares mode_changed signal and exported properties" do
    entry = Godot::ClassRegistry.find("SUCCCamera").not_nil!
    entry.signals.map(&.name).should contain("mode_changed")
    props = entry.properties.map(&.name)
    props.should contain("invert_mouse_y")
    props.should contain("yaw_target")
  end
end

describe SUCCPawn do
  it "registers with Godot ClassRegistry as CharacterBody3D" do
    entry = Godot::ClassRegistry.find("SUCCPawn")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("CharacterBody3D")
  end

  it "declares interpolation_speed exported property" do
    entry = Godot::ClassRegistry.find("SUCCPawn").not_nil!
    entry.properties.map(&.name).should contain("interpolation_speed")
  end
end

describe SUCC do
  it "registers with Godot ClassRegistry as CharacterBody3D" do
    entry = Godot::ClassRegistry.find("SUCC")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("CharacterBody3D")
    entry.not_nil!.is_tool.should be_false
  end

  it "declares config Resource export property" do
    entry = Godot::ClassRegistry.find("SUCC").not_nil!
    config_prop = entry.properties.find { |p| p.name == "config" }
    config_prop.should_not be_nil
    config_prop.not_nil!.variant_type.should eq(24)
    config_prop.not_nil!.hint_string.should eq("SUCCConfig")
  end

  it "declares strongly-typed signals for state, jump, landing, and camera mode" do
    entry = Godot::ClassRegistry.find("SUCC").not_nil!
    sigs = entry.signals.map(&.name)
    sigs.should contain("movement_state_changed")
    sigs.should contain("game_state_changed")
    sigs.should contain("jumped")
    sigs.should contain("landed")
    sigs.should contain("camera_mode_changed")
  end

  it "clips velocity against a normal plane (Quake PM_ClipVelocity)" do
    vel = Godot::Vector3.new(0.0_f32, -10.0_f32, 5.0_f32)
    floor_normal = Godot::Vector3.new(0.0_f32, 1.0_f32, 0.0_f32)
    clipped = SUCC.clip_velocity(vel, floor_normal)
    clipped.x.should be_close(0.0_f32, 0.0001_f32)
    clipped.y.should be_close(0.0_f32, 0.0001_f32)
    clipped.z.should be_close(5.0_f32, 0.0001_f32)
  end
end

describe SUCCTestLevel do
  it "registers with Godot ClassRegistry as Node3D" do
    entry = Godot::ClassRegistry.find("SUCCTestLevel")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("Node3D")
  end
end

describe SuccCrPlugin do
  it "registers with Godot ClassRegistry as tool EditorPlugin" do
    entry = Godot::ClassRegistry.find("SuccCrPlugin")
    entry.should_not be_nil
    entry.not_nil!.parent_name.should eq("EditorPlugin")
    entry.not_nil!.is_tool.should be_true
  end
end
