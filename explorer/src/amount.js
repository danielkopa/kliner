// Turning a 256-bit integer into something a person reads without counting
// zeroes. All of it stays in BigInt: a token balance does not survive being
// a JavaScript number, and the one place that matters is the one place people
// look.

export function format(amount, decimals = 18, options = {}) {
    const significant = options.significant ?? 6;
    const negative = amount < 0n;
    let v = negative ? -amount : amount;

    const d = BigInt(decimals);
    const unit = 10n ** d;
    const whole = v / unit;
    const rest = v % unit;

    let fraction = '';
    if (rest > 0n) {
        fraction = rest.toString().padStart(decimals, '0');
        // Keep enough digits to say something, counting from the first that is
        // not a zero, so 0.00001234 does not round away to nothing.
        const lead = fraction.length - fraction.replace(/^0+/, '').length;
        const keep = whole > 0n ? Math.min(significant, 6) : lead + significant;
        fraction = fraction.slice(0, Math.max(keep, 1)).replace(/0+$/, '');
    }

    const head = group(whole.toString());
    const text = fraction ? `${head}.${fraction}` : head;

    if (v > 0n && text.replace(/[0.,]/g, '') === '') {
        return (negative ? '-' : '') + `<0.${'0'.repeat(Math.max(significant - 1, 0))}1`;
    }
    return (negative ? '-' : '') + text;
}

function group(digits) {
    return digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

// Compact form for a dense list: 1.2M rather than 1,200,000.
export function compact(amount, decimals = 18) {
    const unit = 10n ** BigInt(decimals);
    const whole = (amount < 0n ? -amount : amount) / unit;
    const sign = amount < 0n ? '-' : '';
    const steps = [
        [1000000000000n, 'T'], [1000000000n, 'B'], [1000000n, 'M'], [1000n, 'k'],
    ];
    for (const [size, suffix] of steps) {
        if (whole >= size) {
            const scaled = Number(whole * 100n / size) / 100;
            return sign + String(scaled) + suffix;
        }
    }
    return format(amount, decimals, { significant: 4 });
}
