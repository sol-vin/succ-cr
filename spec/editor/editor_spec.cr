require "spec"
require "lapis"
require "../../src/main"

include Lapis::Test

# =============================================================================
# Addon In-Editor Test Suite (spec/editor/editor_spec.cr)
# =============================================================================
# These tests are registered into Lapis::Test::Registry and executed live
# inside the Godot Editor through the Crystal Hub dock (Unit Test Runner tab)
# without opening or switching scenes.

test_suite "SUCC Classes" do
  test "SUCCConfig is registered as a tool Resource" do
    entry = Godot::ClassRegistry.find("SUCCConfig")
    assert_not_nil entry, "Expected SUCCConfig to be registered"
    assert_eq entry.not_nil!.parent_name, "Resource"
    assert_true entry.not_nil!.is_tool
  end

  test "SUCC is registered as CharacterBody3D with signals and config export" do
    entry = Godot::ClassRegistry.find("SUCC")
    assert_not_nil entry, "Expected SUCC to be registered"
    assert_eq entry.not_nil!.parent_name, "CharacterBody3D"
    assert_false entry.not_nil!.is_tool
    props = entry.not_nil!.properties.map(&.name)
    assert_includes props, "config"
    sigs = entry.not_nil!.signals.map(&.name)
    assert_includes sigs, "movement_state_changed"
    assert_includes sigs, "game_state_changed"
    assert_includes sigs, "jumped"
    assert_includes sigs, "landed"
    assert_includes sigs, "camera_mode_changed"
  end

  test "SUCCCamera is registered as SpringArm3D" do
    entry = Godot::ClassRegistry.find("SUCCCamera")
    assert_not_nil entry, "Expected SUCCCamera to be registered"
    assert_eq entry.not_nil!.parent_name, "SpringArm3D"
  end

  test "SUCCPawn is registered as CharacterBody3D" do
    entry = Godot::ClassRegistry.find("SUCCPawn")
    assert_not_nil entry, "Expected SUCCPawn to be registered"
    assert_eq entry.not_nil!.parent_name, "CharacterBody3D"
  end
end

test_case "Editor", "SuccCrPlugin is marked as tool" do
  entry = Godot::ClassRegistry.find("SuccCrPlugin")
  assert_not_nil entry, "Expected SuccCrPlugin to be registered"
  assert_true entry.not_nil!.is_tool, "SuccCrPlugin must have is_tool == true"
end

describe "Addon In-Editor Test Suite" do
  it "registers addon in-editor tests with Lapis::Test" do
    tests = Registry.all_tests
    tests.should_not be_empty
  end
end
