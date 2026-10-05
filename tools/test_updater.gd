extends SceneTree
## Self-update logic (src/core/updater.gd) without the network: which release
## counts as newer, picking this platform's executable out of a GitHub
## release, and swapping the executable on Linux and Windows.
## godot4 --headless -s tools/test_updater.gd

const Updater = preload("res://src/core/updater.gd")
var fails := 0


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %-8s %s" % ["OK  " if ok else "FAIL", name, detail])


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _initialize() -> void:
	var mine := {"sha": "aaa", "time": 1000}
	_check("newer", Updater.is_newer(mine, {"sha": "bbb", "time": 2000}) and not Updater.is_newer(mine, {"sha": "aaa", "time": 3000})
		and not Updater.is_newer(mine, {"sha": "ccc", "time": 500}) and not Updater.is_newer(mine, {}),
		"a later build is newer; the same commit or an older build is not")
	var rel := {"name": "Ultimate Grapple (latest build)", "assets": [
		{"name": "UltimateGrapple-linux-x86_64.zip", "browser_download_url": "https://x/zip", "size": 5},
		{"name": "build.json", "browser_download_url": "https://x/build.json", "size": 60},
		{"name": "ultimate-grapple.x86_64", "browser_download_url": "https://x/lin", "size": 70000000},
		{"name": "UltimateGrapple.exe", "browser_download_url": "https://x/win", "size": 80000000}]}
	_check("assets", str(Updater.pick_asset(rel, false).browser_download_url) == "https://x/lin" and str(Updater.pick_asset(rel, true).browser_download_url) == "https://x/win"
		and Updater.asset_url(rel, "build.json") == "https://x/build.json" and Updater.pick_asset({"assets": []}, false).is_empty(),
		"the Linux / Windows executable and build.json are found in the release")
	var dir := ProjectSettings.globalize_path("user://updater_test")
	DirAccess.make_dir_recursive_absolute(dir)
	# Linux: the new file replaces the executable
	var exe := dir + "/ultimate-grapple.x86_64"
	_write(exe, "old")
	_write(exe + ".download", "new")
	var err := Updater.swap(exe, exe + ".download", false)
	_check("linux", err == "" and FileAccess.get_file_as_string(exe) == "new" and not FileAccess.file_exists(exe + ".download"), "swapped: %s" % (err if err != "" else "ok"))
	# Windows: the running exe moves to .old, the new one takes its name
	var wexe := dir + "/UltimateGrapple.exe"
	_write(wexe, "old")
	_write(wexe + ".download", "new")
	var werr := Updater.swap(wexe, wexe + ".download", true)
	_check("windows", werr == "" and FileAccess.get_file_as_string(wexe) == "new" and FileAccess.get_file_as_string(wexe + ".old") == "old",
		"swapped, old exe kept as .old: %s" % (werr if werr != "" else "ok"))
	_check("source", not Updater.supported(), "running from source: no self-update")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	print("updater: %d failures" % fails)
	quit(0 if fails == 0 else 1)
