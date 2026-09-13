// Prints how every request reads. Not a test — a way to look at the wording.
import { read } from '../src/request.js';
import { explain } from '../src/warn.js';
import { REQUESTS, CONTEXT } from './fixtures.js';

const mark = { stop: '!!', warn: ' !', note: '  ', clear: ' ok' };

for (const [name, request] of Object.entries(REQUESTS)) {
    const out = explain(read(request, CONTEXT), CONTEXT);
    console.log('\n' + name + '   [' + out.level + ']');
    console.log('  ' + out.title);
    for (const r of out.risks) console.log('   ' + (mark[r.level] || '  ') + ' ' + r.title);
}
console.log('');
