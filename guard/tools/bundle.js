// Folds the reader into one classic script for the extension's own world.
// The modules are written so this is a concatenation and nothing else; if that
// stops being true — two files declaring the same name — this refuses.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const ORDER = [
    'src/keccak.js', 'src/hex.js', 'src/amount.js', 'src/known.js',
    'src/calldata.js', 'src/typed.js', 'src/request.js', 'src/warn.js',
    'src/overlay.js',
];

const IMPORT = /^import\s[\s\S]*?from\s+'[^']+';[ \t]*$/gm;
const REEXPORT = /^export\s*\{[^}]*\};[ \t]*$/gm;
const DECLARED = /^export\s+(?:async\s+)?(const|let|function|class)\s+([A-Za-z_$][\w$]*)/gm;

const seen = new Map();
const parts = [];

for (const file of ORDER) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');
    for (const match of source.matchAll(DECLARED)) {
        if (seen.has(match[2])) {
            console.error('Two files declare ' + match[2] + ': ' + seen.get(match[2]) + ' and ' + file);
            process.exit(1);
        }
        seen.set(match[2], file);
    }
    parts.push('/* ' + file + ' */\n' +
        source.replace(IMPORT, '').replace(REEXPORT, '').replace(/^export\s+/gm, '').trim());
}

const banner = [
    '// Kliner Guard — the reader.',
    '//',
    '// Built from src/ by tools/bundle.js. Every line of it is in this repository.',
    '// It makes no network request of any kind: there is no fetch, no XHR, no',
    '// WebSocket and no image beacon anywhere below, which is why the extension',
    '// asks for no permissions and cannot report on you.',
    ''
].join('\n');

const out = banner + '(function(){\n"use strict";\n\n' + parts.join('\n\n') + '\n})();\n';

const target = path.join(root, 'extension', 'guard.js');
fs.writeFileSync(target, out);

// The claim in that banner is worth checking rather than asserting.
const forbidden = /\b(fetch|XMLHttpRequest|WebSocket|EventSource|navigator\.sendBeacon|importScripts)\b/;
const offending = out.split('\n').filter((line) => forbidden.test(line) && !line.trim().startsWith('//'));
if (offending.length) {
    console.error('The reader must not reach the network. Found:\n  ' + offending.join('\n  '));
    process.exit(1);
}

console.log('extension/guard.js  ' + (fs.statSync(target).size / 1024).toFixed(1) + ' kB  · no network calls in it');
