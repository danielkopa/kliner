// Folds the whole app into one file you can open by double-clicking it.
//
// The modules are written so this is a concatenation and nothing more: no
// circular imports, no default exports, no name used twice. If that ever stops
// being true this refuses rather than shipping something subtly broken.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const ORDER = [
    'src/keccak.js',
    'src/hex.js',
    'src/amount.js',
    'src/abi.js',
    'src/flows.js',
    'src/classify.js',
    'src/say.js',
    'src/chains.js',
    'src/rpc.js',
    'src/tokens.js',
    'src/scan.js',
    'src/wallet.js',
    'app.js',
];

const IMPORT = /^import\s[\s\S]*?from\s+'[^']+';[ \t]*$/gm;
const REEXPORT = /^export\s*\{[^}]*\};[ \t]*$/gm;
const DECLARED = /^export\s+(?:async\s+)?(const|let|function|class)\s+([A-Za-z_$][\w$]*)/gm;

const seen = new Map();
const parts = [];

for (const file of ORDER) {
    const source = fs.readFileSync(path.join(root, file), 'utf8');

    for (const match of source.matchAll(DECLARED)) {
        const name = match[2];
        if (seen.has(name)) {
            console.error('Two files both declare ' + name + ': ' + seen.get(name) + ' and ' + file);
            process.exit(1);
        }
        seen.set(name, file);
    }

    const body = source
        .replace(IMPORT, '')
        .replace(REEXPORT, '')
        .replace(/^export\s+/gm, '')
        .trim();

    parts.push('/* ── ' + file + ' ' + '─'.repeat(Math.max(0, 60 - file.length)) + ' */\n\n' + body);
}

const script = parts.join('\n\n');

const page = fs.readFileSync(path.join(root, 'index.html'), 'utf8')
    .replace('<script type="module" src="app.js"></script>',
             '<script type="module">\n' + script + '\n</script>');

fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
const target = path.join(root, 'dist', 'kliner.html');
fs.writeFileSync(target, page);

const kb = (fs.statSync(target).size / 1024).toFixed(1);
console.log('dist/kliner.html  ' + kb + ' kB  — one file, opens without a server');
