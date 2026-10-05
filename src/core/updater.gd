extends Node
## Self-update for the release builds (the GitHub release zips: one exported
## executable with the game inside). On start it asks GitHub for the latest
## release; that release carries build.json (the commit it was built from and
## when) next to the bare executables. If it's newer than the build.json
## baked into this executable, `available` fires; install() then downloads
## the executable for this platform next to ours, swaps it in and restarts.
##
## Only for exported release builds that know their build (res://build.json,
## written by the release workflow): never from source, under nix (read-only
## store) or for the dedicated server.

signal available(info: Dictionary)          # {sha, time, title, date, url, size}
signal progress(text: String, done: bool, ok: bool)

const LATEST_API := "https://api.github.com/repos/malleum/ultimategrapple/releases/latest"
const RELEASES_PAGE := "https://github.com/malleum/ultimategrapple/releases/latest"
const BUILD_PATH := "res://build.json"
const ASSET_LINUX := "ultimate-grapple.x86_64"
const ASSET_WINDOWS := "UltimateGrapple.exe"
const MIN_SIZE := 1024 * 1024   # a real executable is tens of MB

var local := {}        # this build's build.json
var info := {}         # the newer release, once found
var _http: HTTPRequest
var _stage := ""       # "release" / "build" / "download"
var _release := {}
var _dl_path := ""


## Is this a build that can update itself?
static func supported() -> bool:
	if not OS.has_feature("template") or not FileAccess.file_exists(BUILD_PATH):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var exe := OS.get_executable_path()
	return not exe.begins_with("/nix/store") and OS.get_environment("UG_MAIN_PACK") == ""


static func read_build(path := BUILD_PATH) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	return d if d is Dictionary else {}


func _ready() -> void:
	local = read_build()
	# Windows can't overwrite a running exe: the last update renamed the old
	# one out of the way, remove it now
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_done)
	check()


func check() -> void:
	if _stage != "":
		return
	_stage = "release"
	if _http.request(LATEST_API, PackedStringArray(["User-Agent: UltimateGrapple-updater", "Accept: application/vnd.github+json"])) != OK:
		_stage = ""


## The asset this platform runs, from a GitHub release JSON ({} if none).
static func pick_asset(release: Dictionary, windows: bool) -> Dictionary:
	var want := ASSET_WINDOWS if windows else ASSET_LINUX
	for a in release.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == want:
			return a
	return {}


static func asset_url(release: Dictionary, name: String) -> String:
	for a in release.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == name:
			return str(a.get("browser_download_url", ""))
	return ""


## Is `remote` (a release's build.json) a newer build than `mine`?
static func is_newer(mine: Dictionary, remote: Dictionary) -> bool:
	if str(remote.get("sha", "")) == "" or str(remote.get("sha", "")) == str(mine.get("sha", "")):
		return false
	return int(remote.get("time", 0)) > int(mine.get("time", 0))


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var stage := _stage
	_stage = ""
	if stage == "download":
		_finish_download(result, code)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return   # offline / rate limited: try again next start
	match stage:
		"release":
			var r = JSON.parse_string(body.get_string_from_utf8())
			if not r is Dictionary:
				return
			_release = r
			var url := asset_url(r, "build.json")
			if url == "" or pick_asset(r, OS.has_feature("windows")).is_empty():
				return
			_stage = "build"
			_http.request(url, PackedStringArray(["User-Agent: UltimateGrapple-updater"]))
		"build":
			var remote = JSON.parse_string(body.get_string_from_utf8())
			if not (remote is Dictionary and is_newer(local, remote)):
				return
			var asset := pick_asset(_release, OS.has_feature("windows"))
			info = {"sha": str(remote.sha), "time": int(remote.get("time", 0)), "title": str(remote.get("title", "")),
				"date": Time.get_date_string_from_unix_time(int(remote.get("time", 0))),
				"url": str(asset.get("browser_download_url", "")), "size": int(asset.get("size", 0))}
			available.emit(info)


## Download the new executable next to this one, swap it in, restart.
func install() -> void:
	if info.is_empty() or _stage != "":
		return
	var exe := OS.get_executable_path()
	_dl_path = exe + ".download"
	DirAccess.remove_absolute(_dl_path)
	var probe := FileAccess.open(_dl_path, FileAccess.WRITE)
	if probe == null:
		progress.emit("Can't write next to the game (%s). Download the new version from %s" % [exe.get_base_dir(), RELEASES_PAGE], true, false)
		return
	probe.close()
	_http.download_file = _dl_path
	_http.timeout = 0.0
	_stage = "download"
	if _http.request(str(info.url), PackedStringArray(["User-Agent: UltimateGrapple-updater"])) != OK:
		_stage = ""
		_http.download_file = ""
		progress.emit("Couldn't start the download.", true, false)
		return
	progress.emit("Downloading the update...", false, true)


func _process(_dt: float) -> void:
	if _stage == "download":
		var got := _http.get_downloaded_bytes()
		var total := maxi(_http.get_body_size(), int(info.get("size", 0)))
		progress.emit("Downloading the update... %.1f / %.1f MB" % [got / 1048576.0, total / 1048576.0], false, true)


func _finish_download(result: int, code: int) -> void:
	_http.download_file = ""
	var size := 0
	var fa := FileAccess.open(_dl_path, FileAccess.READ)
	if fa:
		size = fa.get_length()
		fa.close()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or size < MIN_SIZE or (int(info.get("size", 0)) > 0 and size != int(info.size)):
		DirAccess.remove_absolute(_dl_path)
		progress.emit("The download failed (%d / HTTP %d). Try again later, or get it from %s" % [result, code, RELEASES_PAGE], true, false)
		return
	var err := swap(OS.get_executable_path(), _dl_path, OS.has_feature("windows"))
	if err != "":
		progress.emit(err, true, false)
		return
	progress.emit("Updated. Restarting...", true, true)
	restart.call_deferred()


## Put `new_path` in place of the executable at `exe`. Linux replaces the file
## (a running program keeps its old copy); Windows can't overwrite a running
## exe but can rename it, so the old one moves to .old (removed next start).
## Returns "" or what went wrong (the old executable is left working).
static func swap(exe: String, new_path: String, windows: bool) -> String:
	if not windows:
		OS.execute("chmod", PackedStringArray(["+x", new_path]))
		if DirAccess.rename_absolute(new_path, exe) != OK:
			return "Couldn't replace %s (no permission?)" % exe
		return ""
	var old := exe + ".old"
	DirAccess.remove_absolute(old)
	if DirAccess.rename_absolute(exe, old) != OK:
		return "Couldn't move %s aside (no permission?)" % exe
	if DirAccess.rename_absolute(new_path, exe) != OK:
		DirAccess.rename_absolute(old, exe)
		return "Couldn't put the new version in place"
	return ""


func restart() -> void:
	var args := OS.get_cmdline_args()
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()
