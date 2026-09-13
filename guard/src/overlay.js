// Kliner Guard — the half that shows you the sentence.
//
// It lives in the extension's own world, so the page cannot read it, style it,
// or click its buttons. It renders into a closed shadow root for the same
// reason. It has no network access and asks for no permissions.

(function () {
    'use strict';

    var host = null;
    var root = null;
    var queue = [];
    var showing = false;

    window.addEventListener('message', function (event) {
        if (event.source !== window) return;
        var data = event.data;
        if (!data || data.channel !== 'kliner-guard' || data.direction !== 'request') return;
        queue.push(data);
        if (!showing) next();
    });

    function answer(id, allow) {
        window.postMessage({ channel: 'kliner-guard', direction: 'verdict', id: id, allow: allow }, '*');
    }

    function next() {
        var item = queue.shift();
        if (!item) { showing = false; hide(); return; }
        showing = true;

        var context = { account: item.account, chainId: item.chainId };
        var out;
        try {
            out = explain(read(item.request, context), context);
        } catch (error) {
            out = {
                title: 'Kliner Guard could not read this one.',
                level: 'warn',
                risks: [{ level: 'warn', code: 'crash', title: 'The reader failed on this request',
                          detail: 'That is a bug in Kliner Guard, not a verdict on the request. ' +
                                  'It is telling you rather than quietly letting it through.' }],
                facts: [],
                reading: {}
            };
        }

        render(out, item, function (allow) {
            answer(item.id, allow);
            next();
        });
    }

    /* ---------- the panel ---------- */

    // The id is different on every page load, and the panel puts itself back if
    // the page tries to remove it. A page that can delete the warning is a page
    // that can hide what it is asking for.
    var HOST_ID = 'kg-' + Math.random().toString(36).slice(2, 10);

    function build() {
        host = document.createElement('div');
        host.id = HOST_ID;
        host.style.cssText = 'all:initial;position:fixed;inset:0;z-index:2147483647;display:none';
        root = host.attachShadow({ mode: 'closed' });
        root.innerHTML =
            '<style>' + CSS + '</style>' +
            '<div class="veil"><div class="panel" role="dialog" aria-modal="true" aria-labelledby="kg-title">' +
            '<div class="top"><span class="mark">Kliner Guard</span><span class="lvl" id="kg-level"></span></div>' +
            '<p class="title" id="kg-title"></p>' +
            '<div class="risks" id="kg-risks"></div>' +
            '<div class="facts" id="kg-facts"></div>' +
            '<details class="raw"><summary>Show me exactly what the site sent</summary><pre id="kg-raw"></pre></details>' +
            '<div class="row"><button class="stop" id="kg-stop">Stop it</button>' +
            '<button class="go" id="kg-go">Sign it anyway</button></div>' +
            '<p class="foot">Kliner Guard read this on your machine. It sent nothing anywhere and cannot sign anything.</p>' +
            '</div></div>';
        (document.documentElement || document.body).appendChild(host);

        try {
            new MutationObserver(function () {
                if (showing && host && !host.isConnected) {
                    (document.documentElement || document.body).appendChild(host);
                }
            }).observe(document.documentElement, { childList: true, subtree: false });
        } catch (e) { /* an old engine still gets the panel, just not the guard on it */ }
    }

    function hide() { if (host) host.style.display = 'none'; }

    function render(out, item, done) {
        if (!host) build();
        host.style.display = 'block';

        var level = root.getElementById('kg-level');
        level.textContent = out.level === 'stop' ? 'Stop' :
                            out.level === 'warn' ? 'Careful' :
                            out.level === 'clear' ? 'Ordinary' : 'Read it';
        level.className = 'lvl lvl-' + out.level;

        root.getElementById('kg-title').textContent = out.title;

        var risks = root.getElementById('kg-risks');
        risks.textContent = '';
        out.risks.forEach(function (risk) {
            var box = document.createElement('div');
            box.className = 'risk lvl-' + risk.level;
            var head = document.createElement('div');
            head.className = 'rt';
            head.textContent = risk.title;
            var body = document.createElement('div');
            body.className = 'rd';
            body.textContent = risk.detail;
            box.appendChild(head); box.appendChild(body);
            risks.appendChild(box);
        });

        var facts = root.getElementById('kg-facts');
        facts.textContent = '';
        out.facts.forEach(function (fact) {
            var line = document.createElement('div');
            line.className = 'fact';
            line.textContent = fact;
            facts.appendChild(line);
        });

        try {
            root.getElementById('kg-raw').textContent = JSON.stringify(item.request, null, 2);
        } catch (e) {
            root.getElementById('kg-raw').textContent = 'unprintable';
        }

        var stop = root.getElementById('kg-stop');
        var go = root.getElementById('kg-go');
        go.textContent = out.level === 'stop' ? 'Sign it anyway' : 'Sign it';
        go.className = 'go' + (out.level === 'stop' ? ' quiet' : '');

        stop.onclick = function () { done(false); };
        go.onclick = function () { done(true); };

        // The safe choice is the one your finger is already on.
        setTimeout(function () { try { stop.focus(); } catch (e) {} }, 0);
    }

    var CSS = [
        ':host{all:initial}',
        '*{box-sizing:border-box;font-family:ui-sans-serif,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}',
        '.veil{position:fixed;inset:0;background:rgba(10,10,9,.55);display:flex;align-items:center;',
        '  justify-content:center;padding:20px;overflow:auto}',
        '.panel{background:#fdfdfc;color:#161614;width:min(520px,100%);border-radius:3px;',
        '  padding:22px 24px 18px;box-shadow:0 24px 70px rgba(0,0,0,.34);font-size:14px;line-height:1.55}',
        '@media (prefers-color-scheme:dark){.panel{background:#141413;color:#f0f0ec}}',
        '.top{display:flex;justify-content:space-between;align-items:baseline;',
        '  border-bottom:1px solid rgba(128,128,120,.28);padding-bottom:10px}',
        '.mark{font-size:11px;letter-spacing:.18em;text-transform:uppercase;font-weight:600}',
        '.lvl{font-size:11px;letter-spacing:.14em;text-transform:uppercase;opacity:.55}',
        '.lvl.lvl-stop{opacity:1;font-weight:600;box-shadow:inset 0 -2px 0 currentColor}',
        '.title{font-size:19px;line-height:1.32;margin:18px 0 0;text-wrap:balance}',
        '.risk{margin-top:14px;padding-left:12px;box-shadow:inset 2px 0 0 currentColor}',
        '.risk.lvl-note{box-shadow:none;padding-left:0;opacity:.72}',
        '.rt{font-weight:600;font-size:13px}',
        '.risk.lvl-note .rt{font-weight:400}',
        '.rd{font-size:13px;opacity:.75;margin-top:2px}',
        '.facts{margin-top:12px;font-size:13px;opacity:.7}',
        '.fact{padding-block:3px;border-bottom:1px solid rgba(128,128,120,.18)}',
        '.raw{margin-top:16px;font-size:12px;opacity:.6}',
        '.raw summary{cursor:pointer}',
        '.raw pre{max-height:190px;overflow:auto;font-family:ui-monospace,Menlo,Consolas,monospace;',
        '  font-size:11px;line-height:1.5;white-space:pre-wrap;word-break:break-all;margin-top:8px}',
        '.row{display:flex;gap:10px;margin-top:20px}',
        'button{appearance:none;font:inherit;font-size:14px;padding:11px 16px;border-radius:2px;cursor:pointer;flex:1 1 0}',
        '.stop{background:#161614;color:#fdfdfc;border:1px solid #161614}',
        '@media (prefers-color-scheme:dark){.stop{background:#f0f0ec;color:#141413;border-color:#f0f0ec}}',
        '.go{background:none;color:inherit;border:1px solid rgba(128,128,120,.5)}',
        '.go.quiet{opacity:.55;font-size:13px;flex:0 0 auto}',
        '.foot{font-size:11px;opacity:.5;margin:14px 0 0}'
    ].join('');
})();
