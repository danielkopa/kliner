// Prints what every fixture reads as. Not a test — a way to look at the wording.
import { classify } from '../src/classify.js';
import { headline } from '../src/say.js';
import * as F from './fixtures.js';

for (const [name, tx] of Object.entries(F.CASES)) {
    const r = classify(tx, F.ME, F.META);
    const h = headline(r, F.META);
    console.log(`${name.padEnd(16)} ${String(r.kind).padEnd(17)} ${h.title}`);
    for (const k of h.risks) console.log(`${''.padEnd(34)}${k.level === 'warn' ? '!' : '·'} ${k.title}`);
}
