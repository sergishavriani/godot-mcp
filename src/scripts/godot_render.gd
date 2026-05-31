#!/usr/bin/env -S godot --script
extends SceneTree

# Render harness for the MCP "capture_scene" tool.
# Loads a scene, waits a few frames so it can initialize and draw, captures the
# main viewport to a PNG, then quits.
#
# IMPORTANT: must be run WITHOUT --headless so a real rendering device exists.
# Invoked as:
#   godot --path <project> [--resolution WxH] --script godot_render.gd <json_params>
# where <json_params> = {"scene_path": "...", "output_path": "...", "frames": <int>}

var frames_to_wait = 5
var frame_count = 0
var output_abs = ""
var capturing = false

func _init():
    var args = OS.get_cmdline_args()
    var script_index = args.find("--script")
    if script_index == -1 or args.size() <= script_index + 2:
        printerr("[ERROR] Missing JSON params argument")
        quit(1)
        return

    var params_json = args[script_index + 2]
    var json = JSON.new()
    if json.parse(params_json) != OK:
        printerr("[ERROR] Failed to parse params JSON: " + params_json)
        quit(1)
        return

    var params = json.get_data()
    if typeof(params) != TYPE_DICTIONARY:
        printerr("[ERROR] Params must be a JSON object")
        quit(1)
        return

    var scene_path = params.get("scene_path", "")
    var output_path = params.get("output_path", "")
    if scene_path == "" or output_path == "":
        printerr("[ERROR] scene_path and output_path are required")
        quit(1)
        return

    if params.has("frames"):
        frames_to_wait = max(1, int(params.frames))

    if not scene_path.begins_with("res://"):
        scene_path = "res://" + scene_path
    if not output_path.begins_with("res://"):
        output_path = "res://" + output_path
    output_abs = ProjectSettings.globalize_path(output_path)

    if not FileAccess.file_exists(scene_path):
        printerr("[ERROR] Scene file does not exist: " + scene_path)
        quit(1)
        return

    var packed = load(scene_path)
    if packed == null:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        quit(1)
        return

    var instance = packed.instantiate()
    if instance == null:
        printerr("[ERROR] Failed to instantiate scene: " + scene_path)
        quit(1)
        return

    root.add_child(instance)
    print("[INFO] Scene loaded, waiting " + str(frames_to_wait) + " frames before capture")
    process_frame.connect(_on_process_frame)

func _on_process_frame():
    frame_count += 1
    if capturing or frame_count < frames_to_wait:
        return
    capturing = true
    if process_frame.is_connected(_on_process_frame):
        process_frame.disconnect(_on_process_frame)

    # Ensure a full frame has actually been drawn before reading back the texture
    await RenderingServer.frame_post_draw

    var img = root.get_texture().get_image()
    if img == null:
        printerr("[ERROR] Failed to read viewport image (no rendering device?)")
        quit(1)
        return

    var err = img.save_png(output_abs)
    if err != OK:
        printerr("[ERROR] Failed to save PNG (error " + str(err) + ") to: " + output_abs)
        quit(1)
        return

    print("[INFO] Screenshot saved to: " + output_abs)
    quit(0)
