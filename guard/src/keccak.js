// keccak256 — the hash Ethereum uses for event topics and address checksums.
//
// This is Keccak, not NIST SHA-3. They differ in one byte of padding
// (0x01 here, 0x06 there), which is why node's crypto.sha3-256 cannot
// stand in for it. No dependency does this for us, so it lives here.
//
// Lanes are BigInt. That is slower than the usual 32-bit-pair trick, but
// it is short enough to read and check by eye, and we hash addresses and
// signatures, not megabytes.

const MASK = (1n << 64n) - 1n;

const RHO = [
     0n,  1n, 62n, 28n, 27n,
    36n, 44n,  6n, 55n, 20n,
     3n, 10n, 43n, 25n, 39n,
    41n, 45n, 15n, 21n,  8n,
    18n,  2n, 61n, 56n, 14n,
];

const RC = [
    0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an,
    0x8000000080008000n, 0x000000000000808bn, 0x0000000080000001n,
    0x8000000080008081n, 0x8000000000008009n, 0x000000000000008an,
    0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
    0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n,
    0x8000000000008003n, 0x8000000000008002n, 0x8000000000000080n,
    0x000000000000800an, 0x800000008000000an, 0x8000000080008081n,
    0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];

const rotl = (v, n) => n === 0n ? v : ((v << n) | (v >> (64n - n))) & MASK;

function permute(A) {
    for (let round = 0; round < 24; round++) {
        // theta
        const C = new Array(5);
        for (let x = 0; x < 5; x++) {
            C[x] = A[x] ^ A[x + 5] ^ A[x + 10] ^ A[x + 15] ^ A[x + 20];
        }
        for (let x = 0; x < 5; x++) {
            const D = C[(x + 4) % 5] ^ rotl(C[(x + 1) % 5], 1n);
            for (let y = 0; y < 5; y++) A[x + 5 * y] ^= D;
        }

        // rho and pi
        const B = new Array(25).fill(0n);
        for (let x = 0; x < 5; x++) {
            for (let y = 0; y < 5; y++) {
                B[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(A[x + 5 * y], RHO[x + 5 * y]);
            }
        }

        // chi
        for (let y = 0; y < 5; y++) {
            for (let x = 0; x < 5; x++) {
                A[x + 5 * y] = B[x + 5 * y] ^
                    ((~B[(x + 1) % 5 + 5 * y] & MASK) & B[(x + 2) % 5 + 5 * y]);
            }
        }

        // iota
        A[0] ^= RC[round];
    }
}

const RATE = 136; // bytes absorbed per block for a 256-bit output

// Returns 32 bytes.
export function keccak256Bytes(input) {
    const bytes = typeof input === 'string'
        ? new TextEncoder().encode(input)
        : Uint8Array.from(input);

    const padded = new Uint8Array(Math.floor(bytes.length / RATE) * RATE + RATE);
    padded.set(bytes);
    padded[bytes.length] = 0x01;
    padded[padded.length - 1] |= 0x80;

    const A = new Array(25).fill(0n);
    for (let off = 0; off < padded.length; off += RATE) {
        for (let lane = 0; lane < RATE / 8; lane++) {
            let v = 0n;
            for (let b = 7; b >= 0; b--) {
                v = (v << 8n) | BigInt(padded[off + lane * 8 + b]);
            }
            A[lane] ^= v;
        }
        permute(A);
    }

    const out = new Uint8Array(32);
    for (let lane = 0; lane < 4; lane++) {
        let v = A[lane];
        for (let b = 0; b < 8; b++) {
            out[lane * 8 + b] = Number(v & 0xffn);
            v >>= 8n;
        }
    }
    return out;
}

// Returns '0x' + 64 hex characters.
export function keccak256(input) {
    let s = '0x';
    for (const b of keccak256Bytes(input)) s += b.toString(16).padStart(2, '0');
    return s;
}
