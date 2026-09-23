#!/usr/bin/env python3
"""Put the window together: one file, nothing fetched."""
import io, json, os, sys
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, 'src')
read = lambda n: io.open(os.path.join(src, n), encoding='utf-8').read()
paths = json.load(open(os.path.join(here, 'mascot-paths.json')))
mascot = ('/* the face: traced once, drawn everywhere */\nconst MASCOT = ' + json.dumps({
    'body': paths['kliner-body'],
    'left': paths['kliner-eye kliner-eye-left'],
    'right': paths['kliner-eye kliner-eye-right'],
}) + ';\n')
script = mascot + read('util.js') + '\n' + read('app.js')
page = read('shell.html').replace('/*STYLE*/', read('style.css')).replace('/*SCRIPT*/', script)
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, 'index.html')
io.open(out, 'w', encoding='utf-8').write(page)
print(out, len(page))
