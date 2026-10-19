require "lapis"

require "./succ_config"
require "./succ_camera"
require "./succ_pawn"
require "./succ"
require "./demo/succ_test_level"

# In non-release builds, load in-editor test suites so they register with Lapis::Test
# and appear in the Crystal Editor Hub (Unit Test Runner tab)
{% unless flag?(:release) %}
  require "../spec/editor/**"
  require "./docs"
{% end %}

# =============================================================================
# succ-cr - EditorPlugin Definition
# =============================================================================
@[Tool]
node SuccCrPlugin < EditorPlugin do
  def _enter_tree : Void
    Godot.print("==================================================================")
    Godot.print("  [LapisAddon] [SuccCrPlugin] SUCC (Crystal) activated in Editor!")
    Godot.print("  [CRYSTAL_ADDON_VERIFIED_SUCCESS_8A3F1E] SUCCConfig, SUCC, SUCCCamera, SUCCPawn registered.")
    Godot.print("==================================================================")
  end

  def _exit_tree : Void
    Godot.print("  [LapisAddon] [SuccCrPlugin] SUCC (Crystal) deactivated in Editor.")
  end
end
