// A JSON-RPC client small enough to read in one sitting.
//
// It speaks to a list of endpoints and moves on when one of them is unwell,
// which public endpoints frequently are. There is no key, no account, and no
// server of ours between you and the chain.

export class Rpc {
    constructor(urls, options = {}) {
        this.urls = Array.isArray(urls) ? [...urls] : [urls];
        this.timeout = options.timeout ?? 15000;
        this.fetch = options.fetch ?? globalThis.fetch?.bind(globalThis);
        this.id = 0;
        this.onError = options.onError ?? (() => {});
    }

    async send(method, params = []) {
        const [answer] = await this.batch([{ method, params }]);
        if (answer.error) throw new RpcError(answer.error, method);
        return answer.result;
    }

    // One HTTP request for many calls. This is the difference between a page
    // that loads and a page that spends a minute counting to fifty.
    async batch(calls) {
        if (!calls.length) return [];
        const payload = calls.map((c) => ({
            jsonrpc: '2.0',
            id: ++this.id,
            method: c.method,
            params: c.params || [],
        }));

        let lastError = null;
        for (let attempt = 0; attempt < this.urls.length; attempt++) {
            const url = this.urls[0];
            try {
                const body = await this.post(url, payload);
                const byId = new Map(body.map((r) => [r.id, r]));
                return payload.map((p) => byId.get(p.id) ?? { error: { message: 'no answer' } });
            } catch (error) {
                lastError = error;
                this.onError(url, error);
                this.urls.push(this.urls.shift()); // try the next one next time
            }
        }
        throw lastError ?? new Error('no endpoint answered');
    }

    async post(url, payload) {
        const stop = new AbortController();
        const timer = setTimeout(() => stop.abort(), this.timeout);
        try {
            const response = await this.fetch(url, {
                method: 'POST',
                headers: { 'content-type': 'application/json' },
                body: JSON.stringify(payload),
                signal: stop.signal,
            });
            if (!response.ok) throw new Error(url + ' answered ' + response.status);
            const body = await response.json();
            return Array.isArray(body) ? body : [body];
        } finally {
            clearTimeout(timer);
        }
    }

    // Conveniences, named the way the chain names them.
    blockNumber()             { return this.send('eth_blockNumber'); }
    getTransaction(hash)      { return this.send('eth_getTransactionByHash', [hash]); }
    getReceipt(hash)          { return this.send('eth_getTransactionReceipt', [hash]); }
    getBlock(n, full = false) { return this.send('eth_getBlockByNumber', [n, full]); }
    getBalance(address)       { return this.send('eth_getBalance', [address, 'latest']); }
    getCode(address)          { return this.send('eth_getCode', [address, 'latest']); }
    call(to, data)            { return this.send('eth_call', [{ to, data }, 'latest']); }
    getLogs(filter)           { return this.send('eth_getLogs', [filter]); }
}

export class RpcError extends Error {
    constructor(error, method) {
        super(method + ': ' + (error.message || 'failed'));
        this.code = error.code;
        this.method = method;
    }
}

export const hexBlock = (n) => '0x' + BigInt(n).toString(16);
