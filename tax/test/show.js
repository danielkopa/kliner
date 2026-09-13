// Prints the year the way a person would read it.
import { compute } from '../src/compute.js';
import { euros, coins, format, EUR } from '../src/decimal.js';
import { YEAR } from './fixtures.js';

for (const method of ['fifo', 'average']) {
    const out = compute(YEAR, { method, otherIncome: '40000' });
    console.log('\n=== ' + method.toUpperCase() + ' ===');
    console.log('disposals: ' + out.counts.disposals + '  (' + out.counts.gains + ' gains, ' + out.counts.losses + ' losses)');
    for (const d of out.disposals) {
        console.log('  ' + String(d.when).slice(0, 10) + '  ' + coins(d.amount, d.asset).padEnd(22) +
            'got ' + euros(d.proceeds).padStart(12) + '  cost ' + euros(d.cost).padStart(12) +
            '  ' + (d.gain >= 0n ? '+' : '') + euros(d.gain));
    }
    console.log('  ----');
    console.log('  gains ' + euros(out.totalGain) + '   losses ' + euros(out.totalLoss) + '   net ' + euros(out.net));
    console.log('  income tax ' + euros(out.incomeTax) + '   health levy 16% ' + euros(out.healthLevy));
    console.log('  OWED ' + euros(out.owed) + '   (' + out.effectiveRate + '% of the gain)');
    if (out.problems.length) {
        console.log('  needs attention:');
        for (const p of out.problems) console.log('   ! ' + String(p.when).slice(0, 10) + '  ' + p.why);
    }
    console.log('  still held:');
    for (const h of out.holdings) console.log('   ' + coins(h.amount, h.asset).padEnd(22) + 'cost ' + euros(h.cost));
}
console.log('');
