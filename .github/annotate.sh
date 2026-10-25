#!/bin/bash
# Posts a failed check's log ($1) as GitHub annotations: its first problems (the cause), what ran before a crash,
# the crash report's reason and stack, and the log's end.
annotate() { [ -n "$2" ] && echo "::error title=$1::${2//$'\n'/%0A}"; }
log=$(grep -v -E "\[Connection\]|^\s*$" "$1")
annotate "First problems" "$(grep -E "Fatal error|fatal|crash|signal|recorded an issue|error:|failed \(|Restarting" <<<"$log" | head -n 20)"
annotate "Before the crash" "$(grep -B 15 -m 1 "Restarting after" <<<"$log")"
report=$(ls -t ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | head -n 1)
[ -n "$report" ] && annotate "Crash report" "$(python3 - "$report" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text[text.index('\n') + 1:])  # the first line is the report's header
print(body.get('exception'), body.get('termination', {}).get('indicator'))
for line in body.get('asi', {}).values(): print(line)
thread = next(t for t in body['threads'] if t.get('triggered'))
images = body.get('usedImages', [])
for frame in thread['frames'][:25]:
    print(images[frame['imageIndex']].get('name', '?') if frame.get('imageIndex') is not None else '?', frame.get('symbol', ''))
PY
)"
annotate "End of log" "$(tail -n 25 <<<"$log")"
