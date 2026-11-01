extends Node3D

const ACCENT := Color("ff335f")
const CYAN := Color("42e8e0")
const DARK := Color("080b12")

var camera: Camera3D
var player_pivot: Node3D
var weapon: Node3D
var muzzle_flash: MeshInstance3D
var muzzle_light: OmniLight3D
var targets: Array[StaticBody3D] = []
var target_material: StandardMaterial3D
var gun_audio: AudioStreamPlayer
var hit_audio: AudioStreamPlayer

var playing := false
var paused := false
var ended := false
var aim_mode := "single"
var menu_state := "main"
var yaw_target := 0.0
var pitch_target := 0.0
var sensitivity := 1.0
var fov := 90.0
var target_radius := 0.38
var target_color := ACCENT
var target_color_index := 0
var round_duration := 30.0
var time_left := 30.0
var score := 0
var hits := 0
var shots := 0
var combo := 0
var best_combo := 0
var recoil := 0.0
var shot_seed := 13
var reaction_active := false
var reaction_phase := ""
var reaction_wait := 0.0
var reaction_signal_time := 0
var reaction_times: Array[float] = []

var score_label: Label
var accuracy_label: Label
var combo_label: Label
var timer_label: Label
var fps_label: Label
var best_label: Label
var hud_panel: PanelContainer
var center_panel: PanelContainer
var center_title: Label
var center_detail: Label
var start_button: Button
var secondary_button: Button
var exit_button: Button
var pause_label: Label
var settings_panel: PanelContainer
var pause_blur: ColorRect
var scoreboard_panel: PanelContainer
var scoreboard_rows: VBoxContainer
var crosshair: Control
var reaction_overlay: ColorRect
var reaction_label: Label
var size_value: LineEdit
var sensitivity_value: LineEdit
var fov_value: LineEdit
var fps_refresh_time := 0.0
var sensitivity_slider: HSlider
var fov_slider: HSlider
var size_slider: HSlider
var volume_slider: HSlider
var duration_select: OptionButton
var color_select: OptionButton
var crosshair_shape_select: OptionButton
var crosshair_length_slider: HSlider
var crosshair_thickness_slider: HSlider
var crosshair_opacity_slider: HSlider
var crosshair_gap_slider: HSlider
var crosshair_red_slider: HSlider
var crosshair_green_slider: HSlider
var crosshair_blue_slider: HSlider
var crosshair_preview: Control
var crosshair_shape := 0
var crosshair_length := 9.0
var crosshair_thickness := 2.0
var crosshair_opacity := 1.0
var crosshair_gap := 4.0
var crosshair_color := Color.WHITE
var master_volume := 80.0
var results_history: Array = []


func _ready() -> void:
	_build_world()
	_build_weapon()
	_build_ui()
	_load_settings()
	_load_history()
	_build_audio()
	_load_best()
	Input.use_accumulated_input = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_main_menu()
	if "--self-test" in OS.get_cmdline_user_args(): call_deferred("_run_self_test")


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("15191c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aab6bc")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.65
	environment.environment = env
	add_child(environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -24, 0)
	key.light_color = Color("d9e2df")
	key.light_energy = 1.15
	key.shadow_enabled = true
	add_child(key)

	var ceiling_light := OmniLight3D.new()
	ceiling_light.position = Vector3(0, 4.1, -6)
	ceiling_light.light_color = Color("d9fff5")
	ceiling_light.light_energy = 6.0
	ceiling_light.omni_range = 11.0
	ceiling_light.shadow_enabled = true
	add_child(ceiling_light)

	var concrete_floor := _concrete_material(Color("454849"), Color("282b2c"), 13.0)
	var concrete_wall := _concrete_material(Color("666a69"), Color("3b3e3e"), 8.0)
	_make_box("Floor", Vector3(24, 0.22, 30), Vector3(0, -1.72, -6), concrete_floor)
	_make_box("BackWall", Vector3(24, 8.5, 0.42), Vector3(0, 2.35, -14), concrete_wall)
	_make_box("LeftWall", Vector3(0.35, 8.5, 30), Vector3(-11.8, 2.35, -6), concrete_wall)
	_make_box("RightWall", Vector3(0.35, 8.5, 30), Vector3(11.8, 2.35, -6), concrete_wall)
	_make_box("Ceiling", Vector3(24, 0.2, 30), Vector3(0, 6.55, -6), _plain_material(Color("242829"), 1.0))

	# Concrete panel seams on the far wall.
	var seam_mat := _plain_material(Color("262929"), 1.0)
	for x in [-7.8, -3.9, 0.0, 3.9, 7.8]:
		_make_box("WallSeam", Vector3(0.026, 8.0, 0.03), Vector3(x, 2.25, -13.77), seam_mat)
	for y in [-0.15, 2.55, 5.25]:
		_make_box("WallSeam", Vector3(23.2, 0.026, 0.03), Vector3(0, y, -13.77), seam_mat)

	# Overhead industrial fixtures.
	for x in [-4.2, 0.0, 4.2]:
		_make_box("LightHousing", Vector3(2.4, 0.13, 0.6), Vector3(x, 6.38, -6), _plain_material(Color("22282a"), 0.65))
		var lamp := _make_box("LightPanel", Vector3(2.15, 0.04, 0.42), Vector3(x, 6.29, -6), _emissive_material(Color("bfffe8"), 2.6))
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Workbench directly in front of the player.
	var top_mat := _plain_material(Color("303536"), 0.82, 0.18)
	var steel := _plain_material(Color("151a1c"), 0.58, 0.62)
	_make_box("BenchTop", Vector3(5.7, 0.25, 1.55), Vector3(0, -0.72, -4.3), top_mat)
	_make_box("BenchFront", Vector3(5.7, 0.34, 0.12), Vector3(0, -0.96, -3.58), steel)
	for x in [-2.35, 2.35]:
		_make_box("BenchLeg", Vector3(0.22, 1.45, 0.25), Vector3(x, -1.18, -4.25), steel)
		_make_box("BenchFoot", Vector3(0.75, 0.12, 0.42), Vector3(x, -1.57, -4.18), steel)
	_make_box("BenchGlow", Vector3(5.45, 0.025, 0.035), Vector3(0, -0.835, -3.505), _emissive_material(CYAN, 1.8))

	# Range lane dividers and distant utility crates add depth.
	for x in [-8.3, 8.3]:
		_make_box("LaneRail", Vector3(0.09, 0.09, 17), Vector3(x, -1.45, -5), steel)
	for x in [-8.8, 7.9]:
		_make_box("Crate", Vector3(1.3, 1.2, 1.25), Vector3(x, -1.0, -11.8), _plain_material(Color("343a39"), 0.95))

	player_pivot = Node3D.new()
	player_pivot.name = "PlayerPivot"
	player_pivot.position = Vector3(0, 0.2, 3.2)
	add_child(player_pivot)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.position = Vector3.ZERO
	camera.fov = fov
	camera.current = true
	player_pivot.add_child(camera)


func _build_weapon() -> void:
	weapon = Node3D.new()
	weapon.name = "Glock18CViewModel"
	weapon.position = Vector3(0.82, -0.62, -1.36)
	weapon.rotation_degrees = Vector3(-3, -8, -2)
	camera.add_child(weapon)

	var slide := _plain_material(Color("292d2e"), 0.28, 0.74)
	var polymer := _plain_material(Color("101314"), 0.88, 0.06)
	var steel := _plain_material(Color("070909"), 0.2, 0.9)
	var marking := _plain_material(Color("bbc2bf"), 0.5, 0.24)

	# Glock 18C-inspired squared slide, polymer frame and compensated barrel.
	_make_weapon_box(Vector3(0.34, 0.24, 0.82), Vector3(0, 0, -0.13), slide)
	_make_weapon_box(Vector3(0.31, 0.12, 0.69), Vector3(0, -0.17, -0.07), polymer)
	_make_weapon_box(Vector3(0.285, 0.55, 0.29), Vector3(0, -0.43, 0.12), polymer, Vector3(-14, 0, 0))
	_make_weapon_box(Vector3(0.25, 0.075, 0.27), Vector3(0, -0.71, 0.19), steel)
	# Trigger guard and trigger.
	_make_weapon_box(Vector3(0.035, 0.2, 0.27), Vector3(-0.145, -0.27, -0.14), polymer, Vector3(0, 0, -20))
	_make_weapon_box(Vector3(0.035, 0.2, 0.27), Vector3(0.145, -0.27, -0.14), polymer, Vector3(0, 0, 20))
	_make_weapon_box(Vector3(0.29, 0.045, 0.12), Vector3(0, -0.38, -0.18), polymer)
	_make_weapon_box(Vector3(0.035, 0.16, 0.035), Vector3(0, -0.29, -0.1), marking, Vector3(18, 0, 0))
	# Rear slide serrations, compensation cuts and iron sights.
	for z in [0.12, 0.17, 0.22, 0.27]:
		_make_weapon_box(Vector3(0.355, 0.018, 0.018), Vector3(0, 0.015, z), steel)
	for z in [-0.37, -0.3, -0.23]:
		_make_weapon_box(Vector3(0.13, 0.018, 0.045), Vector3(0, 0.128, z), steel)
	_make_weapon_box(Vector3(0.08, 0.055, 0.045), Vector3(0, 0.15, -0.5), steel)
	_make_weapon_box(Vector3(0.15, 0.06, 0.05), Vector3(0, 0.15, 0.25), steel)
	# Short exposed barrel and dark muzzle bore.
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new(); barrel_mesh.top_radius = 0.075; barrel_mesh.bottom_radius = 0.075; barrel_mesh.height = 0.16; barrel_mesh.radial_segments = 20
	barrel.mesh = barrel_mesh; barrel.material_override = steel; barrel.position = Vector3(0, 0, -0.59); barrel.rotation_degrees.x = 90; weapon.add_child(barrel)
	var bore := MeshInstance3D.new()
	var bore_mesh := CylinderMesh.new(); bore_mesh.top_radius = 0.047; bore_mesh.bottom_radius = 0.047; bore_mesh.height = 0.012; bore_mesh.radial_segments = 20
	bore.mesh = bore_mesh; bore.material_override = _plain_material(Color.BLACK, 1.0); bore.position = Vector3(0, 0, -0.675); bore.rotation_degrees.x = 90; weapon.add_child(bore)

	# Low-poly gloved hands.
	var glove := _plain_material(Color("202728"), 0.94)
	_make_weapon_sphere(Vector3(0.29, 0.25, 0.38), Vector3(0.13, -0.62, 0.24), glove)
	_make_weapon_sphere(Vector3(0.36, 0.25, 0.42), Vector3(0.27, -0.79, 0.34), glove)

	muzzle_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.12
	flash_mesh.height = 0.3
	muzzle_flash.mesh = flash_mesh
	muzzle_flash.material_override = _emissive_material(Color("ffd166"), 7.5)
	muzzle_flash.position = Vector3(0, 0, -0.71)
	muzzle_flash.scale = Vector3(0.7, 0.7, 1.7)
	muzzle_flash.visible = false
	weapon.add_child(muzzle_flash)

	muzzle_light = OmniLight3D.new()
	muzzle_light.position = muzzle_flash.position
	muzzle_light.light_color = Color("ff9d35")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.0
	weapon.add_child(muzzle_light)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# Real-time screen blur shown only behind the ESC menu.
	pause_blur = ColorRect.new()
	pause_blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blur_shader := Shader.new()
	blur_shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_strength = 3.2;
void fragment() {
	vec4 scene = textureLod(screen_texture, SCREEN_UV, blur_strength);
	scene.rgb *= vec3(0.48, 0.52, 0.58);
	COLOR = scene;
}
"""
	var blur_material := ShaderMaterial.new()
	blur_material.shader = blur_shader
	pause_blur.material = blur_material
	pause_blur.visible = false
	root.add_child(pause_blur)

	hud_panel = PanelContainer.new()
	hud_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud_panel.offset_left = 24
	hud_panel.offset_top = 20
	hud_panel.offset_right = -24
	hud_panel.offset_bottom = 86
	hud_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.05, 0.075, 0.94), Color(0.18, 0.22, 0.28, 1)))
	root.add_child(hud_panel)
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 34)
	hud_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_panel.add_child(hud_row)
	score_label = _hud_value(hud_row, "得分", "000000")
	accuracy_label = _hud_value(hud_row, "命中率", "—")
	combo_label = _hud_value(hud_row, "连击", "×0")
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hud_row.add_child(spacer)
	timer_label = _hud_value(hud_row, "剩余时间", "00:30", ACCENT)
	fps_label = _hud_value(hud_row, "帧率", "FPS 0", CYAN)

	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	settings_panel.offset_left = -330
	settings_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.052, 0.985), Color(0.15, 0.19, 0.24, 1)))
	root.add_child(settings_panel)
	var side_margin := MarginContainer.new()
	side_margin.add_theme_constant_override("margin_left", 24)
	side_margin.add_theme_constant_override("margin_right", 24)
	side_margin.add_theme_constant_override("margin_top", 26)
	side_margin.add_theme_constant_override("margin_bottom", 24)
	settings_panel.add_child(side_margin)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_margin.add_child(settings_scroll)
	var settings_box := VBoxContainer.new()
	settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_box.add_theme_constant_override("separation", 12)
	settings_scroll.add_child(settings_box)
	var kicker := _label("PAUSE MENU", 10, ACCENT); kicker.add_theme_constant_override("outline_size", 0); settings_box.add_child(kicker)
	settings_box.add_child(_label("训练设置", 22, Color.WHITE))
	var resume_button := Button.new()
	resume_button.text = "继续训练  →"
	resume_button.custom_minimum_size.y = 44
	resume_button.add_theme_stylebox_override("normal", _panel_style(ACCENT, ACCENT))
	resume_button.add_theme_stylebox_override("hover", _panel_style(Color("ff5277"), Color("ff5277")))
	resume_button.pressed.connect(_resume_game)
	settings_box.add_child(resume_button)
	var finish_button := Button.new()
	finish_button.text = "结束训练并结算"
	finish_button.custom_minimum_size.y = 38
	finish_button.pressed.connect(_end_round)
	settings_box.add_child(finish_button)
	settings_box.add_child(HSeparator.new())

	sensitivity_slider = _setting_slider(settings_box, "鼠标灵敏度", 0.1, 3.0, 0.05, 1.0)
	sensitivity_value = sensitivity_slider.get_meta("value_input")
	sensitivity_slider.value_changed.connect(func(v: float): sensitivity = v; sensitivity_value.text = "%.2f" % v; _save_settings())
	volume_slider = _setting_slider(settings_box, "主音量", 0, 100, 1, 80)
	volume_slider.value_changed.connect(_on_volume_changed)
	fov_slider = _setting_slider(settings_box, "视野范围 FOV", 60, 120, 1, 90)
	fov_value = fov_slider.get_meta("value_input")
	fov_slider.value_changed.connect(func(v: float): fov = v; camera.fov = v; fov_value.text = "%d" % int(v); _save_settings())
	size_slider = _setting_slider(settings_box, "目标大小", 0.18, 0.7, 0.01, 0.38)
	size_value = size_slider.get_meta("value_input")
	size_slider.value_changed.connect(_on_size_changed)

	settings_box.add_child(_label("训练时长", 12, Color("b9c2cd")))
	duration_select = OptionButton.new()
	duration_select.add_item("不限时", 0); duration_select.add_item("15 秒", 15); duration_select.add_item("30 秒", 30); duration_select.add_item("60 秒", 60)
	duration_select.selected = 2
	duration_select.item_selected.connect(func(index: int): round_duration = float(duration_select.get_item_id(index)); _save_settings())
	settings_box.add_child(duration_select)
	settings_box.add_child(_label("目标颜色", 12, Color("b9c2cd")))
	color_select = OptionButton.new()
	color_select.add_item("脉冲红"); color_select.add_item("电光青"); color_select.add_item("荧光绿"); color_select.add_item("紫罗兰")
	color_select.item_selected.connect(_on_color_selected)
	settings_box.add_child(color_select)
	settings_box.add_child(HSeparator.new())
	settings_box.add_child(_label("准星设置", 14, Color.WHITE))
	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size.y = 104
	preview_panel.add_theme_stylebox_override("panel", _panel_style(Color("080c12"), Color("26313b")))
	settings_box.add_child(preview_panel)
	crosshair_preview = preload("res://crosshair.gd").new()
	crosshair_preview.set_anchors_preset(Control.PRESET_CENTER)
	crosshair_preview.position = Vector2(-40, -40)
	crosshair_preview.size = Vector2(80, 80)
	preview_panel.add_child(crosshair_preview)
	crosshair_shape_select = OptionButton.new()
	crosshair_shape_select.add_item("十字"); crosshair_shape_select.add_item("圆点"); crosshair_shape_select.add_item("圆环"); crosshair_shape_select.add_item("十字 + 中心点")
	crosshair_shape_select.item_selected.connect(func(index: int): crosshair_shape = index; _apply_crosshair(); _save_settings())
	settings_box.add_child(crosshair_shape_select)
	crosshair_length_slider = _setting_slider(settings_box, "准星长度", 2, 20, 1, 9)
	crosshair_length_slider.value_changed.connect(func(v: float): crosshair_length = v; (crosshair_length_slider.get_meta("value_input") as LineEdit).text = "%d" % int(v); _apply_crosshair(); _save_settings())
	crosshair_thickness_slider = _setting_slider(settings_box, "准星粗细", 1, 6, 0.5, 2)
	crosshair_thickness_slider.value_changed.connect(func(v: float): crosshair_thickness = v; (crosshair_thickness_slider.get_meta("value_input") as LineEdit).text = "%.1f" % v; _apply_crosshair(); _save_settings())
	crosshair_gap_slider = _setting_slider(settings_box, "中心间距", 0, 16, 1, 4)
	crosshair_gap_slider.value_changed.connect(func(v: float): crosshair_gap = v; (crosshair_gap_slider.get_meta("value_input") as LineEdit).text = "%d" % int(v); _apply_crosshair(); _save_settings())
	crosshair_opacity_slider = _setting_slider(settings_box, "准星浓淡", 0.1, 1.0, 0.05, 1.0)
	crosshair_opacity_slider.value_changed.connect(func(v: float): crosshair_opacity = v; (crosshair_opacity_slider.get_meta("value_input") as LineEdit).text = "%.2f" % v; _apply_crosshair(); _save_settings())
	settings_box.add_child(_label("准星颜色 RGB", 12, Color("b9c2cd")))
	crosshair_red_slider = _setting_slider(settings_box, "红色 R", 0, 255, 1, 255)
	crosshair_red_slider.value_changed.connect(func(v: float): _on_crosshair_rgb(0, v))
	crosshair_green_slider = _setting_slider(settings_box, "绿色 G", 0, 255, 1, 255)
	crosshair_green_slider.value_changed.connect(func(v: float): _on_crosshair_rgb(1, v))
	crosshair_blue_slider = _setting_slider(settings_box, "蓝色 B", 0, 255, 1, 255)
	crosshair_blue_slider.value_changed.connect(func(v: float): _on_crosshair_rgb(2, v))
	settings_box.add_child(HSeparator.new())
	best_label = _label("个人最佳  0", 13, CYAN)
	settings_box.add_child(best_label)
	var tip := _label("移动鼠标瞄准 · 左键射击\nESC 暂停/释放鼠标\n参数可在训练中实时调整", 11, Color("6f7b89"))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_box.add_child(tip)
	settings_panel.visible = false

	# Hold-Tab scoreboard, styled as a compact competitive match panel.
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	scoreboard_panel.position = Vector2(-390, -255)
	scoreboard_panel.size = Vector2(780, 510)
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.052, 0.975), Color(0.22, 0.29, 0.36, 1)))
	root.add_child(scoreboard_panel)
	var board_margin := MarginContainer.new()
	board_margin.add_theme_constant_override("margin_left", 30); board_margin.add_theme_constant_override("margin_right", 30)
	board_margin.add_theme_constant_override("margin_top", 26); board_margin.add_theme_constant_override("margin_bottom", 26)
	scoreboard_panel.add_child(board_margin)
	var board_box := VBoxContainer.new(); board_box.add_theme_constant_override("separation", 10); board_margin.add_child(board_box)
	var board_kicker := _label("PERFORMANCE ARCHIVE", 10, ACCENT); board_box.add_child(board_kicker)
	board_box.add_child(_label("训练成绩", 26, Color.WHITE))
	var board_hint := _label("按住 TAB 查看 · 松开隐藏", 11, Color("718090")); board_box.add_child(board_hint)
	board_box.add_child(HSeparator.new())
	var header := HBoxContainer.new(); board_box.add_child(header)
	_add_score_cell(header, "场次", 170, Color("718090"))
	_add_score_cell(header, "得分", 140, Color("718090"))
	_add_score_cell(header, "命中率", 140, Color("718090"))
	_add_score_cell(header, "最高连击", 140, Color("718090"))
	_add_score_cell(header, "时长", 100, Color("718090"))
	board_box.add_child(HSeparator.new())
	scoreboard_rows = VBoxContainer.new(); scoreboard_rows.add_theme_constant_override("separation", 4); board_box.add_child(scoreboard_rows)
	scoreboard_panel.visible = false

	crosshair = preload("res://crosshair.gd").new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-40, -40)
	crosshair.size = Vector2(80, 80)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)

	reaction_overlay = ColorRect.new()
	reaction_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reaction_overlay.color = Color("14181d")
	reaction_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reaction_overlay)
	reaction_label = _label("等待颜色变化……", 30, Color.WHITE)
	reaction_label.set_anchors_preset(Control.PRESET_CENTER)
	reaction_label.position = Vector2(-260, -60)
	reaction_label.size = Vector2(520, 120)
	reaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reaction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reaction_overlay.add_child(reaction_label)
	reaction_overlay.visible = false

	center_panel = PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	center_panel.position = Vector2(-260, -190)
	center_panel.size = Vector2(520, 380)
	center_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.052, 0.96), ACCENT))
	root.add_child(center_panel)
	var center_margin := MarginContainer.new()
	center_margin.add_theme_constant_override("margin_left", 38); center_margin.add_theme_constant_override("margin_right", 38)
	center_margin.add_theme_constant_override("margin_top", 36); center_margin.add_theme_constant_override("margin_bottom", 34)
	center_panel.add_child(center_margin)
	var center_box := VBoxContainer.new(); center_box.alignment = BoxContainer.ALIGNMENT_CENTER; center_box.add_theme_constant_override("separation", 16); center_margin.add_child(center_box)
	var ready := _label("PRECISION PROTOCOL", 10, ACCENT); ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; center_box.add_child(ready)
	center_title = _label("VOID//AIM", 30, Color.WHITE); center_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; center_box.add_child(center_title)
	center_detail = _label("选择要进行的训练项目", 13, Color("909baa")); center_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; center_box.add_child(center_detail)
	start_button = Button.new(); start_button.text = "练枪  →"; start_button.custom_minimum_size = Vector2(0, 50); start_button.add_theme_color_override("font_color", Color.WHITE); start_button.add_theme_stylebox_override("normal", _panel_style(ACCENT, ACCENT)); start_button.add_theme_stylebox_override("hover", _panel_style(Color("ff5277"), Color("ff5277"))); start_button.pressed.connect(_primary_menu_action); center_box.add_child(start_button)
	secondary_button = Button.new(); secondary_button.text = "反应速度测试"; secondary_button.custom_minimum_size = Vector2(0, 46); secondary_button.pressed.connect(_secondary_menu_action); center_box.add_child(secondary_button)
	exit_button = Button.new(); exit_button.text = "退出游戏"; exit_button.custom_minimum_size = Vector2(0, 40); exit_button.pressed.connect(func(): get_tree().quit()); center_box.add_child(exit_button)

	pause_label = _label("已暂停 · ESC 继续", 13, Color.WHITE)
	pause_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pause_label.position = Vector2(-100, -66)
	pause_label.size = Vector2(200, 34)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.visible = false
	root.add_child(pause_label)


func _build_audio() -> void:
	gun_audio = AudioStreamPlayer.new()
	gun_audio.stream = _make_pistol_shot()
	gun_audio.volume_db = -2.5
	add_child(gun_audio)
	hit_audio = AudioStreamPlayer.new()
	hit_audio.stream = _make_hit_confirm()
	hit_audio.volume_db = -4.0
	add_child(hit_audio)


func _process(delta: float) -> void:
	fps_refresh_time += delta
	if fps_refresh_time >= 0.25:
		fps_refresh_time = 0.0
		fps_label.text = "FPS %d" % Engine.get_frames_per_second()

	recoil = move_toward(recoil, 0.0, delta * 7.4)
	var kick := sin(recoil * PI)
	weapon.position = Vector3(0.82, -0.62 + kick * 0.11, -1.36 + kick * 0.08)
	weapon.rotation_degrees.x = -3.0 + kick * 10.5

	if reaction_active:
		_process_reaction(delta)

	if playing and not paused:
		if round_duration > 0.0: time_left = maxf(0.0, time_left - delta)
		_update_hud()
		if round_duration > 0.0 and time_left <= 0.0:
			_end_round()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_TAB and not event.echo:
		scoreboard_panel.visible = event.pressed
		if event.pressed: _update_scoreboard()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode == KEY_ENTER:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and playing and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mouse_delta: Vector2 = event.screen_relative
		var scale := sensitivity * 0.00135
		yaw_target -= mouse_delta.x * scale
		pitch_target = clampf(pitch_target - mouse_delta.y * scale, deg_to_rad(-48), deg_to_rad(48))
		player_pivot.rotation.y = yaw_target
		camera.rotation.x = pitch_target
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if reaction_active:
			_reaction_click()
		elif playing and not paused and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_shoot()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if reaction_active: _cancel_reaction()
		elif playing:
			if paused: _resume_game()
			else: _pause_game()
		elif menu_state == "aim_select": _show_main_menu()


func _toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _show_main_menu() -> void:
	menu_state = "main"
	playing = false; paused = false; reaction_active = false
	_clear_targets()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud_panel.visible = false
	crosshair.visible = false
	pause_blur.visible = false
	settings_panel.visible = false
	scoreboard_panel.visible = false
	reaction_overlay.visible = false
	center_title.text = "VOID//AIM"
	center_detail.text = "选择要进行的训练项目"
	start_button.text = "练枪  →"
	secondary_button.text = "反应速度测试"
	exit_button.visible = true
	center_panel.visible = true


func _show_aim_mode_menu() -> void:
	menu_state = "aim_select"
	center_title.text = "选择练枪模式"
	center_detail.text = "单目标：精准定位 · 六目标：快速目标切换"
	start_button.text = "单目标模式  →"
	secondary_button.text = "六目标模式  →"
	exit_button.visible = false


func _primary_menu_action() -> void:
	match menu_state:
		"main": _show_aim_mode_menu()
		"aim_select": aim_mode = "single"; start_game()
		"aim_result": start_game()
		"reaction_result": _start_reaction_test()


func _secondary_menu_action() -> void:
	match menu_state:
		"main": _start_reaction_test()
		"aim_select": aim_mode = "six"; start_game()
		"aim_result", "reaction_result": _show_main_menu()


func _start_reaction_test() -> void:
	menu_state = "reaction"
	playing = false; paused = false; ended = false
	reaction_active = true
	reaction_times.clear()
	_clear_targets()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	center_panel.visible = false
	exit_button.visible = false
	hud_panel.visible = false
	crosshair.visible = false
	pause_blur.visible = false
	settings_panel.visible = false
	scoreboard_panel.visible = false
	reaction_overlay.visible = true
	_begin_reaction_wait()


func _begin_reaction_wait() -> void:
	reaction_phase = "waiting"
	reaction_wait = randf_range(1.6, 4.2)
	reaction_overlay.color = Color("171b20")
	reaction_label.text = "第 %d / 5 次\n等待颜色变化……" % (reaction_times.size() + 1)


func _process_reaction(delta: float) -> void:
	if reaction_phase == "waiting":
		reaction_wait -= delta
		if reaction_wait <= 0.0:
			reaction_phase = "signal"
			reaction_signal_time = Time.get_ticks_msec()
			reaction_overlay.color = Color("24b86a")
			reaction_label.text = "点击！"
	elif reaction_phase == "cooldown":
		reaction_wait -= delta
		if reaction_wait <= 0.0: _begin_reaction_wait()


func _reaction_click() -> void:
	if reaction_phase == "signal":
		var elapsed := float(Time.get_ticks_msec() - reaction_signal_time)
		reaction_times.append(elapsed)
		if reaction_times.size() >= 5:
			_finish_reaction_test()
		else:
			reaction_phase = "cooldown"
			reaction_wait = 0.9
			reaction_overlay.color = Color("17242b")
			reaction_label.text = "%.0f ms\n准备下一次……" % elapsed
	elif reaction_phase == "waiting":
		reaction_phase = "cooldown"
		reaction_wait = 1.0
		reaction_overlay.color = Color("9c263d")
		reaction_label.text = "过早！本次不计入\n请等待绿色出现"


func _finish_reaction_test() -> void:
	reaction_active = false
	reaction_overlay.visible = false
	var total := 0.0
	for value in reaction_times: total += value
	var average := total / reaction_times.size()
	menu_state = "reaction_result"
	center_title.text = "反应测试完成"
	center_detail.text = "五次平均：%.0f ms\n单次：%s ms" % [average, ", ".join(reaction_times.map(func(v: float): return "%.0f" % v))]
	start_button.text = "再次测试  →"
	secondary_button.text = "返回主菜单"
	exit_button.visible = false
	center_panel.visible = true


func _cancel_reaction() -> void:
	reaction_active = false
	reaction_overlay.visible = false
	_show_main_menu()


func _run_self_test() -> void:
	await get_tree().process_frame
	aim_mode = "six"
	start_game()
	await get_tree().physics_frame
	assert(targets.size() == 6, "六目标模式未生成六个目标")
	_pause_game()
	assert(not crosshair.visible, "ESC 菜单打开后准星仍可见")
	_resume_game()
	assert(crosshair.visible, "恢复训练后准星未恢复")
	round_duration = 0.0
	_update_hud()
	assert(timer_label.text == "不限时", "不限时 HUD 显示错误")
	playing = false
	_clear_targets()
	reaction_times = [180.0, 200.0, 220.0, 190.0, 210.0]
	_finish_reaction_test()
	assert("200 ms" in center_detail.text, "反应测试平均值计算错误")
	print("VOID_AIM_SELF_TEST_OK")
	get_tree().quit()


func start_game() -> void:
	_clear_targets()
	score = 0; hits = 0; shots = 0; combo = 0; best_combo = 0
	time_left = round_duration
	playing = true; paused = false; ended = false
	yaw_target = player_pivot.rotation.y; pitch_target = camera.rotation.x
	center_panel.visible = false
	pause_label.visible = false
	settings_panel.visible = false
	pause_blur.visible = false
	scoreboard_panel.visible = false
	hud_panel.visible = true
	crosshair.visible = true
	reaction_overlay.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var target_count := 6 if aim_mode == "six" else 1
	for i in target_count: _spawn_target()
	_update_hud()


func _pause_game() -> void:
	if not playing or ended: return
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_label.visible = true
	pause_blur.visible = true
	settings_panel.visible = true
	crosshair.visible = false


func _resume_game() -> void:
	paused = false
	pause_label.visible = false
	pause_blur.visible = false
	settings_panel.visible = false
	crosshair.visible = true
	yaw_target = player_pivot.rotation.y
	pitch_target = camera.rotation.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _shoot() -> void:
	shots += 1
	recoil = 1.0
	gun_audio.stop(); gun_audio.play()
	muzzle_flash.visible = true
	muzzle_light.light_energy = 4.5
	var current_shot := shots
	get_tree().create_timer(0.045).timeout.connect(func():
		if shots == current_shot:
			muzzle_flash.visible = false
			muzzle_light.light_energy = 0.0
	)

	var center := get_viewport().get_visible_rect().size * 0.5
	var from := camera.project_ray_origin(center)
	var to := from + camera.project_ray_normal(center) * 100.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var tracer_end: Vector3 = result.position if result else to
	_spawn_tracer(muzzle_flash.global_position, tracer_end)
	if result and result.collider in targets:
		var hit_target := result.collider as StaticBody3D
		hits += 1
		combo += 1
		best_combo = maxi(best_combo, combo)
		score += 100 + mini(combo, 20) * 4
		var hit_material := (hit_target.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		_hit_effect(result.position, hit_material.emission)
		hit_audio.stop(); hit_audio.play()
		targets.erase(hit_target)
		hit_target.queue_free()
		_spawn_target()
	else:
		combo = 0
	_update_hud()


func _spawn_target() -> void:
	var new_target := StaticBody3D.new()
	new_target.name = "TargetSphere"
	var mesh_node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = target_radius
	sphere.height = target_radius * 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	mesh_node.mesh = sphere
	target_material = _emissive_material(target_color, 2.7)
	mesh_node.material_override = target_material
	new_target.add_child(mesh_node)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new(); shape.radius = target_radius
	collision.shape = shape
	new_target.add_child(collision)
	var candidate := Vector3.ZERO
	for attempt in 20:
		candidate = Vector3(randf_range(-6.4, 6.4), randf_range(-0.1, 3.8), randf_range(-12.8, -7.0))
		if absf(candidate.x) < 3.2 and candidate.y < 0.25: candidate.y = randf_range(0.4, 2.2)
		var clear := true
		for existing in targets:
			if existing.position.distance_to(candidate) < target_radius * 3.2: clear = false; break
		if clear: break
	new_target.position = candidate
	add_child(new_target)
	targets.append(new_target)


func _hit_effect(world_position: Vector3, color: Color) -> void:
	var light := OmniLight3D.new()
	light.position = world_position
	light.light_color = color
	light.light_energy = 5.0
	light.omni_range = 2.5
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.12)
	tween.tween_callback(light.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	var distance := direction.length()
	if distance < 0.01: return
	var tracer := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.009
	mesh.bottom_radius = 0.009
	mesh.height = distance
	mesh.radial_segments = 6
	tracer.mesh = mesh
	tracer.material_override = _emissive_material(Color("ffd47a"), 5.5)
	tracer.position = (from + to) * 0.5
	tracer.quaternion = Quaternion(Vector3.UP, direction.normalized())
	add_child(tracer)
	get_tree().create_timer(0.055).timeout.connect(tracer.queue_free)


func _end_round() -> void:
	if not playing: return
	playing = false; ended = true; paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_blur.visible = false
	settings_panel.visible = false
	crosshair.visible = false
	hud_panel.visible = false
	_clear_targets()
	var accuracy := 0 if shots == 0 else int(round(float(hits) / shots * 100.0))
	var old_best := int(_load_value("best_score", 0))
	var is_record := score > old_best
	if is_record: _save_value("best_score", score)
	_append_history(accuracy)
	menu_state = "aim_result"
	center_title.text = "新的个人最佳！" if is_record else "训练完成"
	center_detail.text = "%s · 得分 %d · 命中率 %d%%\n最高连击 ×%d" % ["六目标" if aim_mode == "six" else "单目标", score, accuracy, best_combo]
	start_button.text = "再次训练  →"
	secondary_button.text = "返回主菜单"
	exit_button.visible = false
	center_panel.visible = true
	best_label.text = "个人最佳  %d" % maxi(old_best, score)


func _update_hud() -> void:
	score_label.text = "%06d" % score
	accuracy_label.text = "—" if shots == 0 else "%d%%" % int(round(float(hits) / shots * 100.0))
	combo_label.text = "×%d" % combo
	timer_label.text = "不限时" if round_duration <= 0.0 else "00:%02d" % int(ceil(time_left))


func _on_size_changed(value: float) -> void:
	target_radius = value
	size_value.text = "%.2f" % value
	_save_settings()
	for item in targets:
		if not is_instance_valid(item): continue
		var mesh := item.get_child(0) as MeshInstance3D
		var sphere := mesh.mesh as SphereMesh
		sphere.radius = value; sphere.height = value * 2.0
		var collision := item.get_child(1) as CollisionShape3D
		(collision.shape as SphereShape3D).radius = value


func _on_color_selected(index: int) -> void:
	var colors := [ACCENT, CYAN, Color("b9f230"), Color("8f6cff")]
	target_color_index = index
	target_color = colors[index]
	for item in targets:
		if not is_instance_valid(item): continue
		var material := (item.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
		material.albedo_color = target_color
		material.emission = target_color
	_save_settings()


func _on_volume_changed(value: float) -> void:
	master_volume = value
	(volume_slider.get_meta("value_input") as LineEdit).text = "%d" % int(value)
	_apply_master_volume()
	_save_settings()


func _apply_master_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, master_volume <= 0.0)
	if master_volume > 0.0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(master_volume / 100.0))


func _clear_targets() -> void:
	for item in targets:
		if is_instance_valid(item): item.queue_free()
	targets.clear()


func _make_box(node_name: String, size: Vector3, position_: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new(); mesh.size = size
	node.mesh = mesh; node.position = position_; node.material_override = material
	add_child(node)
	return node


func _make_weapon_box(size: Vector3, position_: Vector3, material: Material, rotation_: Vector3 = Vector3.ZERO) -> void:
	var node := MeshInstance3D.new(); var mesh := BoxMesh.new(); mesh.size = size
	node.mesh = mesh; node.position = position_; node.rotation_degrees = rotation_; node.material_override = material
	weapon.add_child(node)


func _make_weapon_sphere(scale_: Vector3, position_: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new(); var mesh := SphereMesh.new(); mesh.radius = 0.5; mesh.height = 1.0
	node.mesh = mesh; node.scale = scale_; node.position = position_; node.material_override = material
	weapon.add_child(node)


func _plain_material(color: Color, roughness := 0.7, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color; material.roughness = roughness; material.metallic = metallic
	return material


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _plain_material(color, 0.34)
	material.emission_enabled = true; material.emission = color; material.emission_energy_multiplier = energy
	return material


func _concrete_material(base: Color, dark: Color, scale_: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec3 base_color : source_color;
uniform vec3 dark_color : source_color;
uniform float noise_scale = 10.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);
}
void fragment() {
	float n=noise(UV*noise_scale)+0.45*noise(UV*noise_scale*3.7);
	ALBEDO=mix(dark_color,base_color,clamp(n,0.0,1.0));
	ROUGHNESS=0.92;
	NORMAL_MAP_DEPTH=0.22;
}
"""
	var material := ShaderMaterial.new(); material.shader = shader
	material.set_shader_parameter("base_color", Vector3(base.r, base.g, base.b))
	material.set_shader_parameter("dark_color", Vector3(dark.r, dark.g, dark.b))
	material.set_shader_parameter("noise_scale", scale_)
	return material


func _make_pistol_shot() -> AudioStreamWAV:
	var rate := 44100
	var length := int(rate * 0.23)
	var bytes := PackedByteArray(); bytes.resize(length * 2)
	var rng := RandomNumberGenerator.new(); rng.seed = Time.get_ticks_usec()
	var low_noise := 0.0
	for i in length:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, noise, 0.085)
		var crack := (noise - low_noise) * exp(-t * 72.0) * 0.92
		var blast := low_noise * exp(-t * 20.0) * 0.72
		var body := sin(TAU * (118.0 - t * 240.0) * t) * exp(-t * 23.0) * 0.55
		var slide_click := sin(TAU * 1850.0 * t) * exp(-t * 105.0) * 0.2
		var room_tail := low_noise * exp(-t * 9.0) * 0.14
		var sample := int(clampf(crack + blast + body + slide_click + room_tail, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = sample & 0xff
		bytes[i * 2 + 1] = (sample >> 8) & 0xff
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = rate; wav.stereo = false; wav.data = bytes
	return wav


func _make_hit_confirm() -> AudioStreamWAV:
	var rate := 44100
	var length := int(rate * 0.105)
	var bytes := PackedByteArray(); bytes.resize(length * 2)
	var rng := RandomNumberGenerator.new(); rng.seed = 18092026
	for i in length:
		var t := float(i) / rate
		var first := sin(TAU * 880.0 * t) * exp(-t * 38.0) * 0.52
		var second := sin(TAU * 1320.0 * t) * exp(-t * 47.0) * 0.34
		var tick := rng.randf_range(-1.0, 1.0) * exp(-t * 95.0) * 0.18
		var sample := int(clampf(first + second + tick, -1.0, 1.0) * 32767.0)
		bytes[i * 2] = sample & 0xff
		bytes[i * 2 + 1] = (sample >> 8) & 0xff
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = rate; wav.stereo = false; wav.data = bytes
	return wav


func _hud_value(parent: Container, caption: String, initial: String, color := Color.WHITE) -> Label:
	var box := VBoxContainer.new(); box.custom_minimum_size.x = 105; parent.add_child(box)
	box.add_child(_label(caption, 10, Color("6e7988")))
	var value := _label(initial, 19, color); box.add_child(value); return value


func _setting_slider(parent: VBoxContainer, caption: String, minimum: float, maximum: float, step_: float, initial: float) -> HSlider:
	var row := HBoxContainer.new(); parent.add_child(row)
	var name_label := _label(caption, 12, Color("b9c2cd")); name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(name_label)
	var value_input := LineEdit.new()
	value_input.text = "%.2f" % initial
	value_input.custom_minimum_size = Vector2(76, 30)
	value_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_input.select_all_on_focus = true
	value_input.add_theme_color_override("font_color", ACCENT)
	row.add_child(value_input)
	var slider := HSlider.new(); slider.min_value = minimum; slider.max_value = maximum; slider.step = step_; slider.value = initial; slider.custom_minimum_size.y = 28; slider.set_meta("value_input", value_input); parent.add_child(slider)
	var apply_input := func():
		var entered := clampf(value_input.text.to_float(), minimum, maximum)
		slider.value = snappedf(entered, step_)
	value_input.text_submitted.connect(func(_text: String): apply_input.call(); value_input.release_focus())
	value_input.focus_exited.connect(func(): apply_input.call())
	return slider


func _label(text_: String, size_: int, color: Color) -> Label:
	var label := Label.new(); label.text = text_; label.add_theme_font_size_override("font_size", size_); label.add_theme_color_override("font_color", color)
	return label


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background
	style.border_color = border; style.set_border_width_all(1); style.set_corner_radius_all(2)
	style.content_margin_left = 18; style.content_margin_right = 18; style.content_margin_top = 12; style.content_margin_bottom = 12
	return style


func _add_score_cell(row: HBoxContainer, text_: String, width: float, color: Color) -> Label:
	var cell := _label(text_, 12, color)
	cell.custom_minimum_size.x = width
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cell)
	return cell


func _update_scoreboard() -> void:
	for child in scoreboard_rows.get_children(): child.queue_free()
	if playing:
		var current_accuracy := 0 if shots == 0 else int(round(float(hits) / shots * 100.0))
		_add_score_row("当前训练", score, current_accuracy, best_combo, int(round_duration), true)
	for i in range(results_history.size() - 1, maxi(-1, results_history.size() - 9), -1):
		var item: Dictionary = results_history[i]
		_add_score_row(str(item.get("label", "历史训练")), int(item.get("score", 0)), int(item.get("accuracy", 0)), int(item.get("combo", 0)), int(item.get("duration", 30)), false)
	if scoreboard_rows.get_child_count() == 0:
		var empty := _label("完成一局训练后，成绩会显示在这里。", 13, Color("718090"))
		empty.custom_minimum_size.y = 52
		scoreboard_rows.add_child(empty)


func _add_score_row(label_: String, score_: int, accuracy_: int, combo_: int, duration_: int, current: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	var color := CYAN if current else Color("d9e0e7")
	_add_score_cell(row, label_, 170, color)
	_add_score_cell(row, "%06d" % score_, 140, color)
	_add_score_cell(row, "%d%%" % accuracy_, 140, color)
	_add_score_cell(row, "×%d" % combo_, 140, color)
	_add_score_cell(row, "%ds" % duration_, 100, color)
	scoreboard_rows.add_child(row)


func _append_history(accuracy: int) -> void:
	results_history.append({
		"label": Time.get_datetime_string_from_system(false, true).replace("T", " "),
		"score": score,
		"accuracy": accuracy,
		"combo": best_combo,
		"duration": int(round_duration)
	})
	while results_history.size() > 20: results_history.pop_front()
	var config := ConfigFile.new(); config.load(_record_path())
	config.set_value("history", "rounds", results_history)
	config.save(_record_path())


func _load_history() -> void:
	var config := ConfigFile.new(); config.load(_record_path())
	var stored: Variant = config.get_value("history", "rounds", [])
	results_history = stored if stored is Array else []


func _save_value(key: String, value: Variant) -> void:
	var path := _record_path()
	var config := ConfigFile.new(); config.load(path); config.set_value("records", key, value); config.save(path)


func _load_value(key: String, default_value: Variant) -> Variant:
	var config := ConfigFile.new(); config.load(_record_path()); return config.get_value("records", key, default_value)


func _record_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://void_aim.cfg")
	return OS.get_executable_path().get_base_dir().path_join("void_aim.cfg")


func _load_best() -> void:
	best_label.text = "个人最佳  %d" % int(_load_value("best_score", 0))


func _save_settings() -> void:
	# UI is built incrementally; avoid saving partial defaults during startup.
	if not sensitivity_slider or not fov_slider or not size_slider or not duration_select or not color_select or not crosshair_shape_select:
		return
	var config := ConfigFile.new()
	config.load(_record_path())
	config.set_value("settings", "sensitivity", sensitivity)
	config.set_value("settings", "fov", fov)
	config.set_value("settings", "target_radius", target_radius)
	config.set_value("settings", "duration", round_duration)
	config.set_value("settings", "target_color", target_color_index)
	config.set_value("settings", "master_volume", master_volume)
	config.set_value("settings", "crosshair_shape", crosshair_shape)
	config.set_value("settings", "crosshair_length", crosshair_length)
	config.set_value("settings", "crosshair_thickness", crosshair_thickness)
	config.set_value("settings", "crosshair_gap", crosshair_gap)
	config.set_value("settings", "crosshair_opacity", crosshair_opacity)
	config.set_value("settings", "crosshair_color", crosshair_color.to_html(true))
	config.save(_record_path())


func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(_record_path())
	sensitivity = clampf(float(config.get_value("settings", "sensitivity", 1.0)), 0.1, 3.0)
	fov = clampf(float(config.get_value("settings", "fov", 90.0)), 60.0, 120.0)
	target_radius = clampf(float(config.get_value("settings", "target_radius", 0.38)), 0.18, 0.7)
	round_duration = float(config.get_value("settings", "duration", 30.0))
	if round_duration not in [0.0, 15.0, 30.0, 60.0]: round_duration = 30.0
	target_color_index = clampi(int(config.get_value("settings", "target_color", 0)), 0, 3)
	var colors := [ACCENT, CYAN, Color("b9f230"), Color("8f6cff")]
	target_color = colors[target_color_index]
	master_volume = clampf(float(config.get_value("settings", "master_volume", 80.0)), 0.0, 100.0)
	crosshair_shape = clampi(int(config.get_value("settings", "crosshair_shape", 0)), 0, 3)
	crosshair_length = clampf(float(config.get_value("settings", "crosshair_length", 9.0)), 2.0, 20.0)
	crosshair_thickness = clampf(float(config.get_value("settings", "crosshair_thickness", 2.0)), 1.0, 6.0)
	crosshair_gap = clampf(float(config.get_value("settings", "crosshair_gap", 4.0)), 0.0, 16.0)
	crosshair_opacity = clampf(float(config.get_value("settings", "crosshair_opacity", 1.0)), 0.1, 1.0)
	crosshair_color = Color.from_string(str(config.get_value("settings", "crosshair_color", "ffffffff")), Color.WHITE)

	sensitivity_slider.set_value_no_signal(sensitivity)
	fov_slider.set_value_no_signal(fov)
	size_slider.set_value_no_signal(target_radius)
	volume_slider.set_value_no_signal(master_volume)
	sensitivity_value.text = "%.2f" % sensitivity
	fov_value.text = "%d" % int(fov)
	size_value.text = "%.2f" % target_radius
	(volume_slider.get_meta("value_input") as LineEdit).text = "%d" % int(master_volume)
	_apply_master_volume()
	camera.fov = fov
	var duration_index := 0 if round_duration == 0.0 else (1 if round_duration == 15.0 else (2 if round_duration == 30.0 else 3))
	duration_select.select(duration_index)
	color_select.select(target_color_index)
	crosshair_shape_select.select(crosshair_shape)
	crosshair_length_slider.set_value_no_signal(crosshair_length)
	crosshair_thickness_slider.set_value_no_signal(crosshair_thickness)
	crosshair_gap_slider.set_value_no_signal(crosshair_gap)
	crosshair_opacity_slider.set_value_no_signal(crosshair_opacity)
	crosshair_red_slider.set_value_no_signal(roundi(crosshair_color.r * 255.0))
	crosshair_green_slider.set_value_no_signal(roundi(crosshair_color.g * 255.0))
	crosshair_blue_slider.set_value_no_signal(roundi(crosshair_color.b * 255.0))
	(crosshair_length_slider.get_meta("value_input") as LineEdit).text = "%d" % int(crosshair_length)
	(crosshair_thickness_slider.get_meta("value_input") as LineEdit).text = "%.1f" % crosshair_thickness
	(crosshair_gap_slider.get_meta("value_input") as LineEdit).text = "%d" % int(crosshair_gap)
	(crosshair_opacity_slider.get_meta("value_input") as LineEdit).text = "%.2f" % crosshair_opacity
	(crosshair_red_slider.get_meta("value_input") as LineEdit).text = "%d" % roundi(crosshair_color.r * 255.0)
	(crosshair_green_slider.get_meta("value_input") as LineEdit).text = "%d" % roundi(crosshair_color.g * 255.0)
	(crosshair_blue_slider.get_meta("value_input") as LineEdit).text = "%d" % roundi(crosshair_color.b * 255.0)
	_apply_crosshair()


func _apply_crosshair() -> void:
	if crosshair and crosshair.has_method("apply_style"):
		crosshair.apply_style(crosshair_shape, crosshair_length, crosshair_thickness, crosshair_color, crosshair_opacity, crosshair_gap)
	if crosshair_preview and crosshair_preview.has_method("apply_style"):
		crosshair_preview.apply_style(crosshair_shape, crosshair_length, crosshair_thickness, crosshair_color, crosshair_opacity, crosshair_gap)


func _on_crosshair_rgb(channel: int, value: float) -> void:
	var normalized := value / 255.0
	if channel == 0:
		crosshair_color.r = normalized
		(crosshair_red_slider.get_meta("value_input") as LineEdit).text = "%d" % int(value)
	elif channel == 1:
		crosshair_color.g = normalized
		(crosshair_green_slider.get_meta("value_input") as LineEdit).text = "%d" % int(value)
	else:
		crosshair_color.b = normalized
		(crosshair_blue_slider.get_meta("value_input") as LineEdit).text = "%d" % int(value)
	_apply_crosshair()
	_save_settings()
