// Money and coin amounts, in integers.
//
// Nothing here is a JavaScript number. 0.1 + 0.2 is not 0.3, and a tax return
// that is out by a cent is a tax return somebody has to explain. Every amount
// is a BigInt at a fixed scale: coins at 18 decimal places, euros at 6 while
// the arithmetic runs and rounded to whole cents only at the very end.

export const COIN = 18;   // places kept for a quantity of an asset
export const EUR = 6;     // places kept for euros mid-calculation
export const CENT = 2;    // places a euro is actually reported in

const TEN = 10n;
const pow = (n) => TEN ** BigInt(n);

// "0.05", 0.05, 5n, "1 234,56" → a BigInt at the given scale.
export function parse(value, scale = COIN) {
    if (typeof value === 'bigint') return value;
    if (value === null || value === undefined || value === '') return 0n;

    let text = String(value).trim().replace(/\s/g, '');
    if (text === '') return 0n;

    // A comma is a decimal point here, but only when it is the only one.
    if (text.indexOf(',') !== -1 && text.indexOf('.') === -1) text = text.replace(',', '.');
    else text = text.replace(/,/g, '');

    const negative = text.startsWith('-');
    if (negative || text.startsWith('+')) text = text.slice(1);

    if (!/^\d*(\.\d*)?([eE][-+]?\d+)?$/.test(text)) {
        throw new Error('That is not a number Kliner can read: ' + JSON.stringify(value));
    }

    // Exchanges export 1.2e-7 more often than anyone would like.
    const e = text.search(/[eE]/);
    let exponent = 0;
    if (e !== -1) { exponent = parseInt(text.slice(e + 1), 10); text = text.slice(0, e); }

    let [whole, fraction = ''] = text.split('.');
    whole = whole || '0';

    let digits = whole + fraction;
    let point = whole.length + exponent;       // how many digits sit left of the point

    if (point < 0) { digits = '0'.repeat(-point) + digits; point = 0; }
    if (point > digits.length) { digits = digits + '0'.repeat(point - digits.length); }

    const left = digits.slice(0, point) || '0';
    let right = digits.slice(point);

    if (right.length > scale) right = right.slice(0, scale);      // truncate, never round up
    else right = right.padEnd(scale, '0');

    const out = BigInt(left + right);
    return negative ? -out : out;
}

export function format(amount, scale = COIN, places) {
    const negative = amount < 0n;
    let v = negative ? -amount : amount;

    const unit = pow(scale);
    let whole = (v / unit).toString();
    let fraction = (v % unit).toString().padStart(scale, '0');

    if (places !== undefined) {
        // Round half up at the requested place.
        const keep = fraction.slice(0, places);
        const next = fraction.charCodeAt(places) - 48;
        let rounded = BigInt(keep || '0');
        if (next >= 5) rounded += 1n;
        const carry = rounded >= pow(places);
        if (carry) { rounded -= pow(places); whole = (BigInt(whole) + 1n).toString(); }
        fraction = places > 0 ? rounded.toString().padStart(places, '0') : '';
    } else {
        fraction = fraction.replace(/0+$/, '');
    }

    const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
    const text = fraction ? grouped + ',' + fraction : grouped;
    return (negative ? '-' : '') + text;
}

export const euros = (amount) => format(amount, EUR, CENT) + ' €';
export const coins = (amount, symbol) => format(amount, COIN) + (symbol ? ' ' + symbol : '');

// Change scale without losing more than the scale allows.
export function rescale(amount, from, to) {
    if (from === to) return amount;
    return to > from ? amount * pow(to - from) : divide(amount, pow(from - to));
}

// Integer division that rounds half away from zero, so a half cent never
// silently disappears in the taxpayer's favour or the tax office's.
export function divide(a, b) {
    if (b === 0n) throw new Error('divide by zero');
    const negative = (a < 0n) !== (b < 0n);
    const x = a < 0n ? -a : a;
    const y = b < 0n ? -b : b;
    const q = x / y;
    const r = x % y;
    const up = r * 2n >= y;
    const out = up ? q + 1n : q;
    return negative ? -out : out;
}

// (a * b) / c, kept exact until the single rounding at the end.
export function scaleBy(a, b, c) {
    return divide(a * b, c);
}

export const ONE_COIN = pow(COIN);
export const ONE_EUR = pow(EUR);
