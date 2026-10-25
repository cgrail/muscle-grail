#!/bin/bash
# Posts a failed check's log ($1) as GitHub annotations: its first problems (the cause), what ran before a crash, and its end.
log=$(grep -v -E "\[Connection\]|^\s*$" "$1")
first=$(grep -E "Fatal error|fatal|crash|signal|recorded an issue|error:|failed \(|Restarting" <<<"$log" | head -n 20)
crash=$(grep -B 15 -m 1 "Restarting after" <<<"$log")
last=$(tail -n 25 <<<"$log")
echo "::error title=First problems::${first//$'\n'/%0A}"
[ -n "$crash" ] && echo "::error title=Before the crash::${crash//$'\n'/%0A}"
echo "::error title=End of log::${last//$'\n'/%0A}"
