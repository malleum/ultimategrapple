#!/usr/bin/env bash
# Big lobby + saved-course pool through a real dedicated server.
#   tools/test_lobby.sh [players]   (default 14: more than the old cap of 12)
set -u
cd "$(dirname "$0")/.."
N=${1:-14}
PORT=24697
godot4 --headless --path . -- --server --port=$PORT >/tmp/ug_lobby_server.log 2>&1 &
SRV=$!
sleep 3
pids=()
for i in $(seq 1 "$N"); do
  godot4 --headless -s tools/test_lobby.gd -- 127.0.0.1:$PORT "P$i" "$N" >"/tmp/ug_lobby_$i.log" 2>&1 &
  pids+=($!)
  [ "$i" = 1 ] && sleep 2
done
fails=0
for p in "${pids[@]}"; do wait "$p" || fails=$((fails + 1)); done
kill "$SRV" 2>/dev/null
grep -h -E "OK|FAIL|lobby of" /tmp/ug_lobby_*.log | sort | uniq -c | sort -rn | head -5
echo "lobby: $N clients, $fails failures"
exit $((fails > 0))
