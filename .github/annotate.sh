#!/bin/bash
# Posts a failed check's log ($1) as GitHub annotations: its first problems (the cause), what ran before a crash,
# the test process's crash report, and the log's end.
annotate() { if [ -n "$2" ]; then echo "::error title=$1::${2//$'\n'/%0A}"; fi; }
log=$(grep -v -E "\[Connection\]|^\s*$" "$1")
annotate "First problems" "$(grep -E "Fatal error|fatal|crash|signal|recorded an issue|error:|failed \(|Restarting" <<<"$log" | head -n 20)"
annotate "Before the crash" "$(grep -B 15 -m 1 "Restarting after" <<<"$log")"
report=$(ls -t ~/Library/Logs/DiagnosticReports/xctest*.ips 2>/dev/null | head -n 1)
if [ -n "$report" ]; then annotate "Crash report" "$(python3 "$(dirname "$0")/crash-report.py" "$report" 2>&1)"; fi
annotate "End of log" "$(tail -n 25 <<<"$log")"
