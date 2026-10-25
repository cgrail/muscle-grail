#!/bin/bash
# Posts the end of a failed check's log ($1) as one GitHub annotation: errors and failing tests are listed last.
lines=$(grep -v -E "\[Connection\]|^\s*$" "$1" | tail -n 25)
echo "::error::${lines//$'\n'/%0A}"
