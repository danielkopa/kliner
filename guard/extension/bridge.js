// Kliner Guard — the thin half, in the page.
//
// This wraps the wallet's request function so that a request can be looked at
// before it goes on. Three rules it never breaks:
//
//   1. It never alters a request. The object the wallet receives is the object
//      the site handed over, unchanged, by identity.
//   2. It never sees a key, a seed, or a signature. It reads a request and
//      forwards it; the wallet does the rest, exactly as before.
//   3. It never adds a request of its own, and it never talks to a network.
//
// The reading itself happens in the extension's own world, where this page
// cannot reach it. All that crosses is a copy of the request and a yes or no.

(function () {
    'use strict';

    var WATCHED = [
        'eth_sendTransaction',
        'eth_signTypedData',
        'eth_signTypedData_v3',
        'eth_signTypedData_v4',
        'personal_sign',
        'eth_sign'
    ];

    var wrapped = new WeakSet();
    var waiting = Object.create(null);
    var counter = 0;

    window.addEventListener('message', function (event) {
        if (event.source !== window) return;
        var data = event.data;
        if (!data || data.channel !== 'kliner-guard' || data.direction !== 'verdict') return;
        var pending = waiting[data.id];
        if (!pending) return;
        delete waiting[data.id];
        pending(data.allow);
    });

    function ask(method, params, account, chainId) {
        return new Promise(function (resolve) {
            var id = 'k' + (++counter) + '-' + Date.now();
            var settled = false;
            waiting[id] = function (allow) { settled = true; resolve(allow); };

            // A copy crosses, never the original.
            var copy;
            try {
                copy = JSON.parse(JSON.stringify({ method: method, params: params }));
            } catch (e) {
                copy = { method: method, params: [] };
            }

            window.postMessage({
                channel: 'kliner-guard',
                direction: 'request',
                id: id,
                request: copy,
                account: account || null,
                chainId: chainId || null
            }, window.location.origin === 'null' ? '*' : window.location.origin);

            // If the reader never answers, the wallet must not be left hanging.
            setTimeout(function () {
                if (!settled) { delete waiting[id]; resolve(true); }
            }, 20000);
        });
    }

    function wrap(provider) {
        if (!provider || typeof provider !== 'object' || wrapped.has(provider)) return provider;
        if (typeof provider.request !== 'function') return provider;
        wrapped.add(provider);

        var original = provider.request.bind(provider);

        provider.request = function (args) {
            var method = args && args.method;
            if (WATCHED.indexOf(method) === -1) return original(args);

            var account = null;
            var chainId = null;
            try {
                account = provider.selectedAddress || null;
                chainId = provider.chainId ? parseInt(provider.chainId, 16) : null;
            } catch (e) { /* a provider that hides these is still readable */ }

            return ask(method, args.params, account, chainId).then(function (allow) {
                if (allow) return original(args); // the original object, untouched
                var refused = new Error('Kliner Guard: you stopped this one.');
                refused.code = 4001; // the code a wallet uses when a person says no
                throw refused;
            });
        };

        return provider;
    }

    // Wrap what is here, and whatever arrives later.
    try {
        var current = window.ethereum;
        if (current) wrap(current);
        Object.defineProperty(window, 'ethereum', {
            configurable: true,
            get: function () { return current; },
            set: function (next) { current = wrap(next); }
        });
    } catch (e) { /* a provider that refuses to be wrapped is left alone */ }

    // Wallets that announce themselves the modern way (EIP-6963).
    window.addEventListener('eip6963:announceProvider', function (event) {
        try { wrap(event.detail && event.detail.provider); } catch (e) {}
    });
    try { window.dispatchEvent(new Event('eip6963:requestProvider')); } catch (e) {}
})();
