#!/usr/bin/env python3
"""Checks APP-STORE.md against App Store Connect's limits and plain-text rules. Exit 1 on any problem."""
import re, sys

LIMITS = {  # heading -> (limit, unit)
    "Subtitle": (30, "chars"), "Untertitel": (30, "chars"),
    "Promotional text": (170, "chars"), "Werbetext": (170, "chars"),
    "Description": (4000, "chars"), "Beschreibung": (4000, "chars"),
    "Keywords": (100, "bytes"), "Schlüsselwörter": (100, "bytes"),
}
FORBIDDEN = "•–—“”„‘’…"  # App Store Connect rejects these, and emoji

text = open(sys.argv[1] if len(sys.argv) > 1 else "APP-STORE.md", encoding="utf-8").read()
problems = []
for heading, body in re.findall(r"^### (.+?)\n+```\n(.*?)\n```", text, re.S | re.M):
    if heading not in LIMITS:
        continue
    limit, unit = LIMITS[heading]
    size = len(body.encode()) if unit == "bytes" else len(body)
    print(f"{heading}: {size}/{limit} {unit}")
    if size > limit:
        problems.append(f"{heading} is {size} {unit}, limit {limit}")
    bad = {c for c in body if c in FORBIDDEN or ord(c) >= 0x1F000}
    if bad:
        problems.append(f"{heading} contains {''.join(sorted(bad))}")
    if unit == "bytes" and ", " in body:
        problems.append(f"{heading} has spaces after commas, which waste bytes")
for p in problems:
    print("ERROR:", p)
sys.exit(1 if problems else 0)
