# Prints a macOS crash report's (.ips) reason and the crashed thread's frames, for annotate.sh.
import json, sys

text = open(sys.argv[1]).read()
body = json.loads(text[text.index('\n') + 1:])  # the first line is a header of its own
print(body.get('exception'), body.get('termination', {}).get('indicator'))
for lines in body.get('asi', {}).values():
    print(*lines, sep='\n')
images = body.get('usedImages', [])
thread = next(t for t in body['threads'] if t.get('triggered'))
for frame in thread['frames'][:25]:
    image = images[frame['imageIndex']].get('name', '?') if 'imageIndex' in frame else '?'
    print(image, frame.get('symbol', ''))
