@tool
extends RefCounted

## Timing log for tracking down slowdowns; does nothing unless /tmp/bte_perf.on exists.
## Totals per name go to /tmp/bte_perf.log every few seconds, and any call over SLOW_MS on its own line.

const FLAG := "/tmp/bte_perf.on"
const LOG := "/tmp/bte_perf.log"
const SLOW_MS := 4.0
const FLUSH_MS := 3000

static var _stats := {}
static var _on := false
static var _checked := 0
static var _flushed := 0


static func begin() -> int:
	return Time.get_ticks_usec()


static func end(name: String, started: int, note := "") -> void:
	if not _enabled():
		return
	var spent := (Time.get_ticks_usec() - started) / 1000.0
	_add(name, spent)
	if spent >= SLOW_MS:
		_write("SLOW %s %.1f ms %s" % [name, spent, note])
	_maybe_flush()


## Editor frame times, from the plugin's _process. Slow frames also log what the engine did.
static func frame(delta: float) -> void:
	if not _enabled():
		return
	var ms := delta * 1000.0
	_add("editor.frame", ms)
	if ms >= 60.0 and (ms < 98.0 or ms > 102.0):
		_write("SLOW editor.frame %.1f ms | %s" % [ms, _engine_state()])
	_maybe_flush()


static var _measuring := false


static func _engine_state() -> String:
	var rids := []
	# Looked up by name: EditorInterface does not exist in exported games, and naming it breaks the script there.
	var editor_viewport: Viewport = null
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		editor_viewport = Engine.get_singleton("EditorInterface").get_editor_viewport_2d()
	if editor_viewport != null:
		rids.append(editor_viewport.get_viewport_rid())
	var main_loop := Engine.get_main_loop() as SceneTree
	if main_loop != null:
		rids.append(main_loop.root.get_viewport_rid())
	if not _measuring:
		_measuring = true
		for rid in rids:
			RenderingServer.viewport_set_measure_render_time(rid, true)
	var cpu := []
	for rid in rids:
		cpu.append("%.1f" % RenderingServer.viewport_get_measured_render_time_cpu(rid))
	return "script=%.1f physics=%.1f draws=%d prims=%d nodes=%d objects=%d setup=%.1f vp_cpu=%s" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_COUNT),
		RenderingServer.get_frame_setup_time_cpu(),
		",".join(cpu)]


static func count(name: String, note := "") -> void:
	if not _enabled():
		return
	_add(name, 0.0)
	if not note.is_empty():
		_write("%s %s" % [name, note])
	_maybe_flush()


static func _add(name: String, spent: float) -> void:
	var s: Array = _stats.get(name, [0, 0.0, 0.0])
	s[0] += 1
	s[1] += spent
	s[2] = maxf(s[2], spent)
	_stats[name] = s


static func _enabled() -> bool:
	var now := Time.get_ticks_msec()
	if now - _checked > 1000:
		_checked = now
		var was := _on
		_on = FileAccess.file_exists(FLAG)
		if _on and not was:
			_write("--- perf log on ---")
			_flushed = now
	return _on


static func _maybe_flush() -> void:
	var now := Time.get_ticks_msec()
	if now - _flushed < FLUSH_MS:
		return
	_flushed = now
	var names := _stats.keys()
	names.sort()
	var lines := PackedStringArray()
	for name in names:
		var s: Array = _stats[name]
		if s[0] > 0:
			lines.append("  %-28s n=%-6d total=%8.1f ms  avg=%6.3f  max=%7.1f" % [name, s[0], s[1], s[1] / s[0], s[2]])
	_stats.clear()
	if not lines.is_empty():
		_write("window:\n" + "\n".join(lines))


static func _write(text: String) -> void:
	var file := FileAccess.open(LOG, FileAccess.READ_WRITE if FileAccess.file_exists(LOG) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("[%.2f] %s" % [Time.get_ticks_msec() / 1000.0, text])
