//
//  MarkdownHTML+HostBridge.swift
//  belvedere
//
//  The MdPreview JS bootstrap injected into every rendered page.
//

import Foundation

// `nonisolated` matters: the targets default to MainActor isolation, and
// rendering runs off the main actor.
nonisolated extension MarkdownHTML {
    // Debug-only perf instrumentation. Routes labelled timings through the
    // host bridge so `[mdp-perf +Xms]` entries land in Xcode's console while
    // diagnosing load-phase regressions. Compiled out of release builds —
    // no-op shims keep call sites unchanged.
    #if DEBUG
    private static let perfBridgeScript = """
    const perfT0 = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : 0;
    function perfNow() {
        return (typeof performance !== 'undefined' && performance.now)
            ? performance.now() - perfT0 : 0;
    }
    function perfLog(label, detail) {
        const dt = perfNow().toFixed(1);
        const msg = '[mdp-perf +' + dt + 'ms] ' + label
            + (detail !== undefined ? ' ' + detail : '');
        try { post({ kind: 'log', message: msg }); } catch (e) {}
    }
    window.MdPreviewPerf = { now: perfNow, log: perfLog, t0: perfT0 };
    perfLog('script eval');

    if (typeof PerformanceObserver === 'function') {
        try {
            // Disconnect after FCP — paint emits at most two entries
            // (first-paint, first-contentful-paint), no need to keep the
            // observer pinned for the WebView's lifetime.
            const seen = new Set();
            const po = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                    perfLog('paint:' + entry.name, entry.startTime.toFixed(1) + 'ms');
                    seen.add(entry.name);
                }
                if (seen.has('first-contentful-paint')) po.disconnect();
            });
            po.observe({ type: 'paint', buffered: true });
        } catch (e) {}
    }
    """
    #else
    private static let perfBridgeScript = """
    function perfNow() { return 0; }
    function perfLog() {}
    window.MdPreviewPerf = { now: perfNow, log: perfLog };
    """
    #endif

    // Always-on host bridge: pushes the document height to the AppKit host via
    // a WKScriptMessageHandler instead of having the host poll. Quietly no-ops
    // when the bridge isn't installed (e.g. Quick Look render).
    // Internal so the WebKit regression tests can exercise the exact
    // `MdPreview.update` pipeline shipped by the app with the bundled
    // DOMPurify and morphdom runtimes.
    #if QUICK_LOOK_EXTENSION
    private static let tablePopupEnabled = false
    #else
    private static let tablePopupEnabled = true
    #endif

    static let hostBridgeScript: String = """
    <script>
    (() => {
        const localized = {
            expandTable: \(javaScriptStringLiteral(NSLocalizedString("Expand Table", comment: "Open a table in full screen"))),
            wrapCode: \(javaScriptStringLiteral(NSLocalizedString("Wrap code", comment: "Code block wrap button"))),
            unwrapCode: \(javaScriptStringLiteral(NSLocalizedString("Unwrap code", comment: "Code block unwrap button"))),
            copyCode: \(javaScriptStringLiteral(NSLocalizedString("Copy code", comment: "Code block copy button accessibility label"))),
            codeCopied: \(javaScriptStringLiteral(NSLocalizedString("Code copied", comment: "Code block copy confirmation accessibility label")))
        };
        let hasHostBridge = false;
        const post = (() => {
            try {
                const h = window.webkit && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.mdPreviewHost;
                if (!h) return () => false;
                hasHostBridge = true;
                return (msg) => {
                    h.postMessage(msg);
                    return true;
                };
            } catch (e) { return () => false; }
        })();

        \(perfBridgeScript)

        function measureHeight() {
            const body = document.body;
            const article = document.querySelector('.markdown-body');
            if (!body || !article) return 1;
            const rect = article.getBoundingClientRect();
            const cs = getComputedStyle(body);
            const pt = parseFloat(cs.paddingTop) || 0;
            const pb = parseFloat(cs.paddingBottom) || 0;
            return Math.max(rect.bottom + pb, pt + article.scrollHeight + pb, 1);
        }

        let last = -1;
        let raf = 0;

        function pushHeight() {
            if (raf) return;
            raf = requestAnimationFrame(() => {
                raf = 0;
                const h = Math.ceil(measureHeight());
                if (h !== last) {
                    last = h;
                    post({ kind: 'height', value: h });
                }
            });
        }

        // Scroll bridge: with compositor-scrolled WKWebView (macOS 26 SDK)
        // the host can't observe scrolling natively — the page reports it.
        let lastScroll = -1;
        let scrollRaf = 0;
        function pushScroll() {
            if (scrollRaf) return;
            scrollRaf = requestAnimationFrame(() => {
                scrollRaf = 0;
                const y = window.scrollY || document.documentElement.scrollTop || 0;
                if (y !== lastScroll) {
                    lastScroll = y;
                    post({ kind: 'scrollPosition', value: y });
                }
            });
        }
        window.addEventListener('scroll', pushScroll, { passive: true });

        window.MdPreviewHost = { pushHeight, measureHeight };

        // Controls injected into the article. Copying and Inspector counts
        // both leave them out.
        const MD_CHROME_SELECTOR = '[data-md-app="code-header"], [data-md-app="table-actions"], .mermaid-hud';
        // A decorated table sits in its wrapper, or in the inner scroller
        // that column resize adds. Both carry the app's marker, which the
        // sanitizer removes from documents.
        const MD_TABLE_PARENT_SELECTOR = '[data-md-app="table-wrap"], [data-md-app="table-scroll"]';
        // Rendered but not document text: diagram zoom controls and KaTeX's
        // visually hidden MathML twin. Inspector counts only.
        const MD_UNCOUNTED_SELECTOR = MD_CHROME_SELECTOR + ', .mermaid-hud, .katex-mathml';

        // Rendered but not text worth pasting: diagrams, footnote back
        // links, and rules. Copy as Plain Text only.
        const MD_PLAIN_SKIPPED_SELECTOR = '.mermaid-figure, .mermaid, .footnote-backrefs, .footnote-backref, hr, .md-source-list-marker';

        // Text of `range` as the preview shows it. Walks the live article
        // rather than a detached clone so computed styles decide block
        // breaks, whitespace collapsing, and visibility (closed <details>,
        // display:none) the way the page renders them.
        //
        // `plain` is Copy as Plain Text: the text a reader would type to
        // reproduce the page without Markdown. Blocks get a blank line
        // between them, list items their bullet, number, or checkbox,
        // footnote references their [n], and math its TeX source.
        function renderedTextOfRange(range, root, { plain = false } = {}) {
            const styles = new Map();
            function styleOf(element) {
                let style = styles.get(element);
                if (!style) {
                    style = getComputedStyle(element);
                    styles.set(element, style);
                }
                return style;
            }
            function whiteSpaceMode(element) {
                const style = styleOf(element);
                const collapse = style.whiteSpaceCollapse;
                if (collapse) {
                    if (collapse === 'preserve-breaks') return 'preserve-breaks';
                    return collapse === 'collapse' ? 'collapse' : 'preserve';
                }
                const ws = style.whiteSpace;
                if (ws === 'pre-line') return 'preserve-breaks';
                return /^(?:pre|pre-wrap|break-spaces)$/.test(ws) ? 'preserve' : 'collapse';
            }
            function isBlock(display) {
                return !/^(?:inline|contents|table-cell|ruby)/.test(display);
            }

            // Separators wait until the next visible text, so leading and
            // trailing breaks never reach the result. Line breaks win over
            // cell tabs, which win over collapsed spaces.
            let text = '';
            let breaks = 0;
            let cell = false;
            let space = false;
            // A list item's marker, written before its first text, and how
            // many list items the walk is inside.
            let prefix = '';
            let listDepth = 0;
            function emit(value) {
                if (text) {
                    if (breaks) {
                        const trailing = /\\n*$/.exec(text)[0].length;
                        text += '\\n'.repeat(Math.max(0, breaks - trailing));
                    } else if (cell) {
                        text += '\\t';
                    } else if (space && !text.endsWith('\\n') && !value.startsWith('\\n')) {
                        text += ' ';
                    }
                }
                breaks = 0;
                cell = false;
                space = false;
                text += prefix + value;
                prefix = '';
            }
            function listMarker(item) {
                const list = item.parentElement;
                let marker = '•';
                if (list && list.nodeName === 'OL') {
                    let number = parseInt(list.getAttribute('start'), 10);
                    if (!Number.isFinite(number)) number = 1;
                    for (let el = item.previousElementSibling; el; el = el.previousElementSibling) {
                        if (el.nodeName === 'LI') number += 1;
                    }
                    marker = number + '.';
                }
                const box = item.classList.contains('task-list-item')
                    && item.querySelector(':scope > input[type=checkbox], :scope > p > input[type=checkbox]');
                if (box) marker = (marker === '•' ? '' : marker + ' ') + (box.checked ? '☑' : '☐');
                return '  '.repeat(listDepth) + marker + ' ';
            }
            function sourceLineMarker(line) {
                let depth = listDepth;
                for (let el = line.parentElement; el && el !== root && el.nodeName !== 'LI'; el = el.parentElement) {
                    if (el.classList.contains('md-source-list-indent-step')) depth += 1;
                }
                const marker = line.querySelector(':scope > .md-source-list-marker');
                const box = marker && marker.querySelector('input[type=checkbox]');
                const text = box ? (box.checked ? '☑' : '☐') : (marker ? marker.textContent.trim() : '•');
                return '  '.repeat(depth) + text + ' ';
            }
            // One line break inside lists, tables, and callouts; a blank
            // line between every other pair of blocks.
            function plainBlockBreaks(node, display) {
                if (listDepth || node.nodeName === 'LI' || display.startsWith('table-')) return 1;
                return node.parentElement?.classList.contains('markdown-alert') ? 1 : 2;
            }
            // Whether the character at `index` takes up space on screen.
            function rendersCharacter(node, index) {
                const probe = document.createRange();
                probe.setStart(node, index);
                probe.setEnd(node, index + 1);
                return probe.getBoundingClientRect().width > 0;
            }
            function addText(node) {
                const from = node === range.startContainer ? range.startOffset : 0;
                const to = node === range.endContainer ? range.endOffset : node.nodeValue.length;
                const selected = node.nodeValue.slice(from, to);
                const parent = node.parentElement;
                if (!selected || !parent || styleOf(parent).visibility !== 'visible') return;
                const mode = whiteSpaceMode(parent);
                if (mode === 'preserve') {
                    emit(selected);
                    return;
                }
                let value = mode === 'preserve-breaks'
                    ? selected.replace(/[ \\t]*\\n[ \\t]*/g, '\\n').replace(/[ \\t]+/g, ' ')
                    : selected.replace(/[ \\t\\n\\r\\f]+/g, ' ');
                // Spaces between text nodes wait for the next visible text so
                // source formatting drops out. A space at a selection edge has
                // no such neighbor in the selection, so ask layout instead.
                if (value.startsWith(' ')) {
                    value = value.slice(1);
                    if (node === range.startContainer && rendersCharacter(node, from)) emit(' ');
                    else space = true;
                }
                const trailingSpace = value.endsWith(' ');
                if (trailingSpace) value = value.slice(0, -1);
                if (value) emit(value);
                if (trailingSpace) {
                    const run = /[ \\t\\n\\r\\f]+$/.exec(selected);
                    if (node === range.endContainer && rendersCharacter(node, from + run.index)) emit(' ');
                    else space = true;
                }
            }

            const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
                acceptNode(node) {
                    if (!range.intersectsNode(node)) return NodeFilter.FILTER_REJECT;
                    if (node.nodeType !== Node.ELEMENT_NODE) return NodeFilter.FILTER_ACCEPT;
                    if (node.matches(MD_UNCOUNTED_SELECTOR)) return NodeFilter.FILTER_REJECT;
                    if (plain && node.matches(MD_PLAIN_SKIPPED_SELECTOR)) return NodeFilter.FILTER_REJECT;
                    // display:contents has no box of its own, so checkVisibility
                    // reports false even though its children render.
                    if (styleOf(node).display === 'contents') return NodeFilter.FILTER_ACCEPT;
                    if (typeof node.checkVisibility === 'function' && !node.checkVisibility())
                        return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            function walkChildren(node) {
                if (!walker.firstChild()) return;
                // A closed <details> renders only its summary.
                const closedDetails = node.nodeName === 'DETAILS' && !node.open;
                do {
                    const child = walker.currentNode;
                    if (closedDetails && child.nodeName !== 'SUMMARY') continue;
                    walk(child);
                } while (walker.nextSibling());
                walker.parentNode();
            }
            function walk(node) {
                if (node.nodeType === Node.TEXT_NODE) {
                    addText(node);
                    return;
                }
                if (node.nodeName === 'BR') {
                    emit('\\n');
                    return;
                }
                const display = styleOf(node).display;
                if (plain) {
                    const tex = node.classList.contains('katex')
                        && node.querySelector('annotation[encoding="application/x-tex"]');
                    if (tex) {
                        if (isBlock(display)) breaks = Math.max(breaks, plainBlockBreaks(node, display));
                        emit(tex.textContent.trim());
                        return;
                    }
                    if (node.matches('sup.footnote-ref')) {
                        emit('[' + node.textContent.trim() + ']');
                        return;
                    }
                }
                const blockBreaks = !isBlock(display) ? 0
                    : plain ? plainBlockBreaks(node, display)
                    : node.nodeName === 'P' ? 2 : 1;
                breaks = Math.max(breaks, blockBreaks);
                if (plain && display === 'table-row') {
                    // Cell by cell, so an empty cell keeps its column.
                    const cells = [...node.children]
                        .filter(child => range.intersectsNode(child)
                            && (typeof child.checkVisibility !== 'function' || child.checkVisibility()))
                        .map(child => renderedTextOfRange(range, child, { plain }).replace(/\\s*\\n\\s*/g, ' '));
                    breaks = Math.max(breaks, 1);
                    if (cells.some(Boolean)) emit(cells.join('\\t'));
                    breaks = Math.max(breaks, 1);
                    return;
                }
                // Over-indented source lines render as list-like lines
                // inside a paragraph (see EscapingHTMLFormatter).
                const sourceLine = plain && node.classList.contains('md-source-list-line');
                const listItem = plain && (node.nodeName === 'LI' || sourceLine);
                // A selection that starts inside the item's text copies
                // that text without the item's marker.
                if (listItem && coversBlockEdge(range, node, 'start')) {
                    prefix = sourceLine ? sourceLineMarker(node) : listMarker(node);
                }
                if (listItem) listDepth += 1;
                walkChildren(node);
                if (listItem) {
                    listDepth -= 1;
                    prefix = '';
                }
                breaks = Math.max(breaks, blockBreaks);
                if (display === 'table-cell') cell = true;
            }
            walkChildren(root);
            return text;
        }

        // The selection's range clipped to the article, or null.
        function selectedArticleRange(article) {
            const selection = window.getSelection();
            if (!article || !selection || selection.isCollapsed || !selection.rangeCount) return null;
            const range = selection.getRangeAt(0);
            if (!range.intersectsNode(article)) return null;
            const clipped = range.cloneRange();
            const bounds = document.createRange();
            bounds.selectNodeContents(article);
            if (clipped.compareBoundaryPoints(Range.START_TO_START, bounds) < 0)
                clipped.setStart(bounds.startContainer, bounds.startOffset);
            if (clipped.compareBoundaryPoints(Range.END_TO_END, bounds) > 0)
                clipped.setEnd(bounds.endContainer, bounds.endOffset);
            return clipped;
        }

        // Copy as Plain Text: the selection as text without Markdown, plus
        // the same HTML a normal copy writes, for rich text fields.
        function plainTextForSelection() {
            const article = document.querySelector('article.markdown-body');
            const range = selectedArticleRange(article);
            if (!range) return null;
            const text = renderedTextOfRange(range, article, { plain: true });
            if (!text) return null;
            const { fragment } = selectionFragment(window.getSelection());
            return { text, html: htmlFromFragment(fragment) };
        }

        // Mirror read-only text selections to the native Inspector. Only the
        // rendered article counts, even when Select All includes page chrome.
        let lastSelectedText = null;
        function pushSelectedText() {
            if (!hasHostBridge) return;
            const article = document.querySelector('article.markdown-body');
            const range = selectedArticleRange(article);
            const text = range ? renderedTextOfRange(range, article) || null : null;
            if (text === lastSelectedText) return;
            lastSelectedText = text;
            post({ kind: 'selectedText', value: text });
        }
        document.addEventListener('selectionchange', pushSelectedText);

        function elementForEventTarget(target) {
            if (target instanceof Element) return target;
            if (target && target.parentElement instanceof Element) return target.parentElement;
            return document.activeElement instanceof Element ? document.activeElement : null;
        }

        function keyBelongsToFocusedControl(target) {
            const el = elementForEventTarget(target);
            if (!el) return false;
            if (el.isContentEditable) return true;
            return !!el.closest([
                'button',
                'input',
                'select',
                'textarea',
                'summary',
                'audio',
                'video',
                '[contenteditable]',
                '[role="button"]',
                '[role="checkbox"]',
                '[role="switch"]',
                '[role="textbox"]',
                '[role="combobox"]',
                '[role="listbox"]',
                '[role="menuitem"]'
            ].join(','));
        }

        function handlePreviewScrollKey(event) {
            if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return false;
            if (keyBelongsToFocusedControl(event.target)) return false;

            const isSpace = event.key === ' ' || event.key === 'Spacebar' || event.code === 'Space';
            if (isSpace) {
                return post({ kind: 'scroll', value: event.shiftKey ? 'pageUp' : 'pageDown' });
            }

            if (event.shiftKey) return false;
            const key = (event.key || '').toLowerCase();
            if (key === 'j') return post({ kind: 'scroll', value: 'lineDown' });
            if (key === 'k') return post({ kind: 'scroll', value: 'lineUp' });
            return false;
        }

        document.addEventListener('keydown', (event) => {
            if (handlePreviewScrollKey(event)) {
                event.preventDefault();
                event.stopPropagation();
            }
        }, true);

        // Deferred images (click-to-load). Two different blocks land in the same place:
        // the CSP refuses a remote image so a document cannot beacon on mere
        // open, and md-asset: containment refuses a local file outside the
        // document's folder. Either way the reader sees a placeholder naming
        // what was withheld, and one click asks the host for it.
        //
        // This markup is built here rather than coming from the document, so
        // it is not attacker-controlled. Document content cannot click the
        // button either: the sanitiser strips scripts and the CSP forbids
        // them, so every activation is a real one.
        const deferredAssets = new Map();
        let deferredSeq = 0;

        function deferredLabel(src) {
            try {
                if (/^https?:/i.test(src)) return new URL(src).host || src;
                return decodeURIComponent(src).split('/').pop() || src;
            } catch (e) { return src; }
        }

        // Whether a reference lies inside the document's own folder. This is
        // a string comparison against the page's base href — no filesystem
        // access — and it is what separates "blocked" from "broken".
        //
        // A file inside the folder was never blocked: resolution is already
        // permitted there, so a failure means it is missing, unreadable or
        // not a format WebKit renders. Offering Load would be offering to do
        // the thing that just failed. Only an out-of-folder reference was
        // refused by containment, and only that one has a remedy.
        //
        // Note the check we can afford here is *location*, not *presence*.
        // Testing whether a file exists is cheap, but doing it for every path
        // a document names would touch the filesystem on the document's behalf
        // at render time, which is the automatic access containment exists to
        // prevent. Presence is discovered when the reader asks, not before.
        function describeFailure(reason) {
            if (reason === 'missing') return 'file missing';
            if (reason === 'notAnImage') return 'load failed: not an image';
            if (reason === 'tooLarge') return 'load failed: too large';
            if (reason === 'unreadable') return 'load failed: cannot read file';
            if (reason === 'unreachable') return 'load failed: no answer from the host';
            // Not a failure at all — the file is fine and was refused. Saying
            // "load failed" for it sends the reader hunting a broken file.
            if (reason === 'outsideFolder') {
                return canGrant
                    ? 'outside this folder'
                    : 'outside this folder — Quick Look cannot load it';
            }
            return 'load failed';
        }

        function isInsideDocumentFolder(src) {
            try {
                const base = document.baseURI || '';
                return !!base && src.startsWith(base);
            } catch (e) { return false; }
        }

        // A grant needs somewhere to send the request. Quick Look registers no
        // `mdPreviewHost` handler, so `post` is a no-op there and nothing can
        // ever answer — a Load button would spin on "Loading…" forever, which
        // is exactly what shipped.
        //
        // That check also happens to be the right *policy* boundary, not just
        // a mechanical one. Quick Look is reached by pressing space on a file
        // Finder selected, so it deliberately offers no grants and no prompts
        // (see docs/FORK-NOTES.md, "Quick Look is a different surface"). The
        // absence of the bridge and the absence of consent are the same fact.
        //
        // Labels still appear there. A label is information, not an
        // affordance: it tells a reader why nothing rendered, and grants
        // nothing. But the in/out-of-folder split is meaningless in Quick
        // Look — the page loads with a nil base URL, so `document.baseURI` is
        // not the document's folder and every reference looks external — so
        // the label stays generic rather than claiming a boundary decision
        // that was never made.
        const canGrant = hasHostBridge;

        function makeDeferredPlaceholder(img) {
            // `img.src` is resolved against the page's <base href>; the raw
            // attribute is whatever the document wrote, which is usually
            // relative. The host needs the resolved one — it cannot act on
            // `../outside.png` — while the label reads better from the raw.
            const src = img.src || img.getAttribute('src') || '';
            const raw = img.getAttribute('src') || src;
            const remote = /^https?:/i.test(src);
            const inside = !remote && isInsideDocumentFolder(src);
            const token = 'd' + (++deferredSeq);
            const box = document.createElement('span');
            box.className = 'mdp-deferred'
                + (remote ? ' mdp-deferred-remote' : '')
                + (inside ? ' mdp-deferred-broken' : '');
            box.setAttribute('data-mdp-deferred', token);
            if (remote) box.setAttribute('data-mdp-remote', '1');
            if (inside) box.setAttribute('data-mdp-broken', '1');

            const label = document.createElement('span');
            label.className = 'mdp-deferred-label';
            // Quick Look's inliner records why it refused each reference, so
            // the label can be exact on a surface where the page has no base
            // URL to reason from.
            const stated = img.getAttribute('data-mdp-refused');
            label.textContent = remote
                // Not "blocked" where it can be loaded: nothing was fetched,
                // and one click fetches it. Quick Look grants nothing, so
                // there the wording stays final.
                ? (canGrant ? 'Remote image — ' : 'Remote image blocked — ')
                    + deferredLabel(src)
                : stated
                    ? deferredLabel(raw) + ' — ' + describeFailure(stated)
                : !canGrant
                    ? deferredLabel(raw) + ' — load failed'
                : inside
                    // Provisional: the host is asked why, and the label is
                    // refined once it answers. WebKit's error event carries no
                    // reason, so "load failed" is all the page knows on its own.
                    ? deferredLabel(raw) + ' — load failed'
                    : deferredLabel(raw);
            label.title = raw;
            box.appendChild(label);

            // A Load button for anything the reader can still ask for: a
            // file outside the document's folder, or a remote image the CSP
            // refused. The refusal is what makes the button meaningful —
            // nothing was fetched on open, so the click is the first and only
            // thing that reaches the network, and it reaches it for one image.
            // An in-folder reference is not offered one: it was never blocked,
            // so the button would only repeat the read that just failed.
            if (!inside && canGrant) {
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'mdp-deferred-load';
                button.textContent = 'Load';
                button.addEventListener('click', (e) => {
                    e.preventDefault();
                    requestDeferred(token);
                });
                box.appendChild(button);
            }

            deferredAssets.set(token, { src, box, img, remote, inside, raw });
            if (inside && canGrant) {
                // Safe without a grant: the app already attempted this exact
                // read while rendering, so asking why it failed reveals
                // nothing new. Only in-folder references are asked about.
                post({ kind: 'classifyDeferredFailure', token: token, src: src });
            }
            img.replaceWith(box);
            updateDeferredBanner();
            return box;
        }

        function requestDeferred(token) {
            const entry = deferredAssets.get(token);
            if (!entry || entry.pending) return;
            entry.pending = true;
            const button = entry.box.querySelector('.mdp-deferred-load');
            if (button) { button.disabled = true; button.textContent = 'Loading…'; }
            post({ kind: 'loadDeferredAsset', token: token, src: entry.src });
        }

        // Called by the host once it has read or fetched the bytes.
        window.MdPreview = window.MdPreview || {};
        window.MdPreview.explainDeferredFailure = (token, reason) => {
            const entry = deferredAssets.get(token);
            if (!entry || !reason) return;
            const label = entry.box.querySelector('.mdp-deferred-label');
            if (label) {
                label.textContent = deferredLabel(entry.raw) + ' — ' + describeFailure(reason);
            }
        };

        window.MdPreview.resolveDeferredAsset = (token, dataURL, refusal) => {
            const entry = deferredAssets.get(token);
            if (!entry) return;
            if (dataURL) {
                const img = entry.img.cloneNode(true);
                img.setAttribute('src', dataURL);
                entry.box.replaceWith(img);
                deferredAssets.delete(token);
            } else {
                entry.pending = false;
                entry.refused = refusal || 'unavailable';
                entry.box.classList.add('mdp-deferred-refused');
                const button = entry.box.querySelector('.mdp-deferred-load');
                if (button) button.remove();
                const label = entry.box.querySelector('.mdp-deferred-label');
                if (label) {
                    // Say that the load was attempted and failed, and why.
                    // "not an image" alone reads as a property of the file
                    // rather than the outcome of the action just taken.
                    label.textContent = label.textContent + ' — ' + describeFailure(entry.refused);
                }
            }
            updateDeferredBanner();
        };

        // "Load all images in this document." Framed around the document
        // because that is how a reader thinks about it, and safe because the
        // host checks each one: anything that is not really an image comes
        // back refused and stays visible as such.
        function updateDeferredBanner() {
            const article = document.querySelector('.markdown-body');
            if (!article) return;
            let banner = article.querySelector('.mdp-deferred-banner');
            // Local only, deliberately. "Load all" is one click standing in
            // for many, which is reasonable for files the reader already has;
            // it is not reasonable for requests to hosts they have not looked
            // at. Remote images stay one click each.
            const pending = [...deferredAssets.values()]
                .filter((e) => !e.refused && !e.remote && !e.inside);
            if (!canGrant || pending.length < 2) { if (banner) banner.remove(); return; }
            if (!banner) {
                banner = document.createElement('div');
                banner.className = 'mdp-deferred-banner';
                const text = document.createElement('span');
                text.className = 'mdp-deferred-banner-text';
                const action = document.createElement('button');
                action.type = 'button';
                action.textContent = 'Load all';
                action.addEventListener('click', (e) => {
                    e.preventDefault();
                    [...deferredAssets.entries()]
                        .filter(([, entry]) => !entry.remote && !entry.inside && !entry.refused)
                        .forEach(([token]) => requestDeferred(token));
                });
                banner.appendChild(text);
                banner.appendChild(action);
                article.insertBefore(banner, article.firstChild);
            }
            banner.querySelector('.mdp-deferred-banner-text').textContent =
                pending.length + ' images outside this folder';
        }

        function deferBlockedImages(root = document) {
            root.querySelectorAll('img:not([data-mdp-deferred-seen])').forEach((img) => {
                img.setAttribute('data-mdp-deferred-seen', '1');
                const src = img.src || img.getAttribute('src') || '';
                if (!src || src.startsWith('data:')) return;
                const fail = () => {
                    if (img.isConnected) makeDeferredPlaceholder(img);
                };
                img.addEventListener('error', fail, { once: true });
                // An image that already failed before the listener attached
                // reports complete with no intrinsic size.
                if (img.complete && img.naturalWidth === 0) fail();
            });
        }
        const codeIcon = (kind) => '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ({
            copy: '<rect x="4" y="8" width="12" height="13" rx="3"/><path d="M8 8V6a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-1"/>',
            check: '<path d="m5 12 4 4L19 6"/>',
            wrap: '<path d="M4 6h16M4 11h12a4 4 0 0 1 0 8h-5m3-3-3 3 3 3M4 16h3"/>',
            unwrap: '<path d="M4 6h16M4 12h16m-4-4 4 4-4 4M4 18h7"/>'
        })[kind] + '</svg>';

        function decorateCodeBlocks(root = document) {
            root.querySelectorAll('pre > code').forEach((code) => {
                const pre = code.parentElement;
                if (!pre || pre.dataset.copyButtonReady === '1') return;
                pre.dataset.copyButtonReady = '1';

                // Wrap pre in a positioned container so the copy button
                // stays pinned regardless of horizontal scroll inside pre.
                const wrap = document.createElement('div');
                wrap.className = 'md-code-wrap';
                pre.parentNode.insertBefore(wrap, pre);
                wrap.appendChild(pre);

                const header = document.createElement('div');
                header.className = 'md-code-header';
                // The app's marker, which documents cannot carry: copying,
                // counts, Expand Table and EPUB leave out only this header,
                // not a document's own element with the same class.
                header.dataset.mdApp = 'code-header';
                const language = document.createElement('span');
                language.className = 'md-code-language';
                language.textContent = pre.dataset.codeLanguage || 'text';
                header.appendChild(language);
                const toggle = document.createElement('button');
                toggle.type = 'button';
                toggle.className = 'md-code-action md-code-toggle-wrap';
                toggle.innerHTML = codeIcon('wrap');
                toggle.title = localized.wrapCode;
                toggle.setAttribute('aria-label', toggle.title);
                toggle.setAttribute('aria-pressed', 'false');
                header.appendChild(toggle);
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'md-code-action md-code-copy';
                button.innerHTML = codeIcon('copy');
                button.title = localized.copyCode;
                button.setAttribute('aria-label', localized.copyCode);
                header.appendChild(button);
                wrap.insertBefore(header, pre);
            });
        }

        // The table wrapper, its actions row and the expand button are marked
        // `data-md-app`, which the sanitizer strips from document content. A
        // document can write its own `class="md-table-expand"` or
        // `md-table-wrap`, since classes are the author's, so the click
        // handler, copy and export go by the marker, never by class.
        function decorateTables(root = document) {
            if (!hasHostBridge || !\(tablePopupEnabled)) return;
            root.querySelectorAll('table').forEach(table => {
                if (table.closest('.md-frontmatter') || table.parentElement.closest('table')
                    || table.parentElement.matches(MD_TABLE_PARENT_SELECTOR)) return;
                const wrap = document.createElement('div');
                wrap.className = 'md-table-wrap';
                wrap.dataset.mdApp = 'table-wrap';
                table.before(wrap);
                wrap.append(table);
                const actions = document.createElement('div');
                actions.className = 'md-table-actions';
                actions.dataset.mdApp = 'table-actions';
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'md-table-expand';
                button.dataset.mdApp = 'table-expand';
                button.innerHTML = \(javaScriptStringLiteral(tableExpandIconSVG));
                button.title = localized.expandTable;
                button.setAttribute('aria-label', localized.expandTable);
                actions.append(button);
                wrap.prepend(actions);
            });
        }
        // Undoes everything column resize adds to a table (below). The
        // Expand button and export use it, so neither copies dragged widths.
        function clearColumnResize(table) {
            table.querySelector('.mdp-column-edge-active')?.classList.remove('mdp-column-edge-active');
            if (!table.classList.contains('mdp-columns-resized')) return;
            const scroller = table.parentElement;
            if (scroller?.dataset.mdApp === 'table-scroll') scroller.replaceWith(table);
            table.querySelector(':scope > colgroup[data-md-app="column-widths"]')?.remove();
            table.classList.remove('mdp-columns-resized');
            table.style.removeProperty('width');
        }
        document.addEventListener('click', event => {
            const button = event.target.closest('[data-md-app="table-expand"]');
            // No `isTrusted` check: documents run no script, so the marker,
            // which they cannot carry, is what keeps a forged button out.
            if (!button) return;
            const table = button.closest('[data-md-app="table-wrap"]')?.querySelector('table');
            if (!table) return;
            event.preventDefault();
            const clone = table.cloneNode(true);
            clone.querySelectorAll('[data-md-app="table-actions"], [data-md-app="code-header"]').forEach(node => node.remove());
            // The table window starts at natural widths, not the document's.
            clearColumnResize(clone);
            let title = '';
            for (const heading of document.querySelectorAll('h1,h2,h3,h4,h5,h6')) {
                if (heading.compareDocumentPosition(table) & Node.DOCUMENT_POSITION_FOLLOWING)
                    title = heading.textContent.trim();
                else break;
            }
            post({kind: 'tablePopup', markdown: clone.outerHTML, title});
        });

        // Drag the edge between two header cells to resize a column, in the
        // document and in the table window; double-click an edge to fit that
        // column to its header text. The first drag fixes each column at its
        // current width, so the others keep theirs. Widths are not saved: a
        // new render, export, or print uses the natural widths.
        if (hasHostBridge && \(tablePopupEnabled)) (() => {
            const edgeSlop = 5;
            const minimumWidth = 40;
            let drag = null;
            let activeCell = null;

            function headerCells(table) {
                const row = table.tHead?.rows[0] ?? table.rows[0];
                return row ? Array.from(row.cells) : [];
            }

            // A cell's start edge is the previous column's end edge, so the
            // pointer can grab an edge from either side of it.
            function edgeAt(event) {
                const cell = event.target.closest?.('th');
                if (!cell) return null;
                // Runs on every pointer move over a header: bail out before
                // the table checks unless the pointer is near a cell side.
                const rect = cell.getBoundingClientRect();
                if (Math.abs(event.clientX - rect.left) > edgeSlop
                    && Math.abs(event.clientX - rect.right) > edgeSlop) return null;
                const table = cell.closest('table');
                if (!table?.parentElement.matches(MD_TABLE_PARENT_SELECTOR)) return null;
                const cells = headerCells(table);
                const index = cells.indexOf(cell);
                if (index < 0 || cells.some(c => c.colSpan > 1)
                    || table.querySelector(':scope > colgroup:not([data-md-app="column-widths"])')) return null;
                const rtl = getComputedStyle(table).direction === 'rtl';
                const end = rtl ? rect.left : rect.right;
                const start = rtl ? rect.right : rect.left;
                if (Math.abs(event.clientX - end) <= edgeSlop) return { table, cells, index, rtl };
                if (index > 0 && Math.abs(event.clientX - start) <= edgeSlop)
                    return { table, cells, index: index - 1, rtl };
                return null;
            }

            function fixColumns(table, cells) {
                const existing = table.querySelector(':scope > colgroup[data-md-app="column-widths"]');
                if (existing) return Array.from(existing.children);
                const widths = cells.map(cell => cell.getBoundingClientRect().width);
                const group = document.createElement('colgroup');
                group.dataset.mdApp = 'column-widths';
                const cols = widths.map(width => {
                    const col = document.createElement('col');
                    col.style.width = `${width}px`;
                    return group.appendChild(col);
                });
                table.prepend(group);
                // Fixed widths need a real table box, which cannot scroll, so
                // an inner box scrolls it. The wrapper stays put, and with it
                // the Expand button.
                // Keep the reader's place: before this, the table itself
                // scrolled horizontally.
                const scrollLeft = table.scrollLeft;
                const scroller = document.createElement('div');
                scroller.dataset.mdApp = 'table-scroll';
                table.before(scroller);
                scroller.append(table);
                table.classList.add('mdp-columns-resized');
                table.style.width = `${widths.reduce((sum, width) => sum + width, 0)}px`;
                // Only after the width is set: until then the table fits the box.
                scroller.scrollLeft = scrollLeft;
                return cols;
            }

            // Measures the header text on one line, so the column is just
            // wide enough for its name. Body cells keep wrapping in it.
            function fitColumn(table, cells, index) {
                const col = fixColumns(table, cells)[index];
                const cell = cells[index];
                const range = document.createRange();
                range.selectNodeContents(cell);
                cell.style.whiteSpace = 'nowrap';
                const textWidth = range.getBoundingClientRect().width;
                cell.style.removeProperty('white-space');
                const style = getComputedStyle(cell);
                const padding = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
                const width = Math.max(minimumWidth, Math.ceil(textWidth + padding) + 1);
                const tableWidth = parseFloat(table.style.width) - parseFloat(col.style.width) + width;
                col.style.width = `${width}px`;
                table.style.width = `${tableWidth}px`;
            }

            function showEdge(cell) {
                if (cell === activeCell) return;
                activeCell?.classList.remove('mdp-column-edge-active');
                activeCell = cell;
                cell?.classList.add('mdp-column-edge-active');
            }

            function endDrag() {
                drag = null;
                showEdge(null);
                document.documentElement.classList.remove('mdp-column-resizing');
            }

            document.addEventListener('pointermove', event => {
                // The release can go to a context menu instead of the page.
                if (drag && !(event.buttons & 1)) endDrag();
                if (!drag) {
                    const edge = edgeAt(event);
                    showEdge(edge ? edge.cells[edge.index] : null);
                    return;
                }
                const delta = (event.clientX - drag.x) * (drag.rtl ? -1 : 1);
                const width = Math.max(minimumWidth, drag.width + delta);
                drag.col.style.width = `${width}px`;
                drag.table.style.width = `${drag.tableWidth - drag.width + width}px`;
            });
            document.addEventListener('pointerdown', event => {
                // Control-click opens the context menu on macOS.
                if (event.button !== 0 || event.ctrlKey) return;
                const edge = edgeAt(event);
                if (!edge) return;
                // Without this the drag selects the header text.
                event.preventDefault();
                const col = fixColumns(edge.table, edge.cells)[edge.index];
                drag = {
                    table: edge.table, col, rtl: edge.rtl, x: event.clientX,
                    width: parseFloat(col.style.width),
                    tableWidth: parseFloat(edge.table.style.width),
                };
                document.documentElement.classList.add('mdp-column-resizing');
                event.target.setPointerCapture?.(event.pointerId);
            });
            // A double-click starts its word selection on mousedown, which
            // the pointerdown handler alone does not stop.
            document.addEventListener('mousedown', event => {
                if (edgeAt(event)) event.preventDefault();
            });
            document.addEventListener('pointerup', endDrag);
            document.addEventListener('pointercancel', endDrag);
            document.addEventListener('dblclick', event => {
                const edge = edgeAt(event);
                if (!edge) return;
                event.preventDefault();
                fitColumn(edge.table, edge.cells, edge.index);
            });
        })();

        function selectionFragment(selection) {
            const fragment = document.createDocumentFragment();
            for (let i = 0; i < selection.rangeCount; i += 1) {
                fragment.appendChild(selection.getRangeAt(i).cloneContents());
            }
            const buttons = fragment.querySelectorAll(MD_CHROME_SELECTOR);
            buttons.forEach((button) => button.remove());
            return { fragment, removedButtons: buttons.length > 0 };
        }

        // Copy as Markdown. The host keeps `window.MdPreview.source` (the
        // document's Markdown) current, and block elements carry their
        // source line range. A selection that covers whole blocks copies
        // those source lines, so lists keep their bullets, links their
        // targets, and code its fences. Partial first or last blocks
        // contribute their selected text; a selection inside one block
        // returns null and copies as text.
        let sourceLineCache = null;
        function sourceLines() {
            const source = window.MdPreview.source;
            if (typeof source !== 'string') return null;
            if (!sourceLineCache || sourceLineCache.source !== source) {
                sourceLineCache = { source, lines: source.split('\\n') };
            }
            return sourceLineCache.lines;
        }
        function sourceSpan(block) {
            const start = Number(block.dataset.sourceStart || block.dataset.sourceLine);
            const end = Number(block.dataset.sourceEnd || block.dataset.sourceLine);
            return Number.isInteger(start) && Number.isInteger(end) && start > 0 && end >= start
                ? { start, end } : null;
        }
        function coversBlockEdge(range, block, edge) {
            const probe = document.createRange();
            probe.selectNodeContents(block);
            if (edge === 'start') probe.setEnd(range.startContainer, range.startOffset);
            else probe.setStart(range.endContainer, range.endOffset);
            return probe.toString().trim() === '';
        }
        function selectedTextWithin(range, block) {
            const clipped = document.createRange();
            clipped.selectNodeContents(block);
            if (clipped.compareBoundaryPoints(Range.START_TO_START, range) < 0) {
                clipped.setStart(range.startContainer, range.startOffset);
            }
            if (clipped.compareBoundaryPoints(Range.END_TO_END, range) > 0) {
                clipped.setEnd(range.endContainer, range.endOffset);
            }
            return clipped.toString();
        }
        function markdownForSelection(selection) {
            selection = selection || window.getSelection();
            const lines = sourceLines();
            if (!lines || !selection || selection.rangeCount !== 1) return null;
            const range = selection.getRangeAt(0);
            if (range.collapsed) return null;
            // Select All ranges over the whole body, so ask for overlap, not
            // containment; the block lookups below stay inside the article.
            const article = document.querySelector('.markdown-body');
            if (!article || !range.intersectsNode(article)) return null;
            // DOM order is not source order: footnote definitions render at
            // the end of the article. Take the earliest source start and the
            // latest source end over every block the selection touches,
            // preferring the innermost block on ties so a partial list item
            // contributes its text while the rest of the list copies as source.
            let startBlock = null, endBlock = null, first = null, last = null;
            for (const block of article.querySelectorAll('[data-source-line]')) {
                if (!range.intersectsNode(block)) continue;
                const span = sourceSpan(block);
                if (!span) continue;
                if (!first || span.start <= first.start) { first = span; startBlock = block; }
                if (!last || span.end >= last.end) { last = span; endBlock = block; }
            }
            if (!startBlock || !endBlock) return null;
            if (last.end < first.start) return null;
            const slice = (from, to) => lines.slice(from - 1, to).join('\\n');
            const startWhole = coversBlockEdge(range, startBlock, 'start');
            const endWhole = coversBlockEdge(range, endBlock, 'end');
            // Nothing rendered lies outside the selection at an edge: extend
            // that edge to the document boundary, so a whole-document copy
            // also carries what renders nothing, such as link reference
            // definitions at the end.
            if (startWhole && coversBlockEdge(range, article, 'start')) first = { start: 1, end: first.end };
            if (endWhole && coversBlockEdge(range, article, 'end')) last = { start: last.start, end: lines.length };
            if (startBlock === endBlock || startBlock.contains(endBlock) || endBlock.contains(startBlock)) {
                if (!startWhole || !endWhole) return null;
                return slice(Math.min(first.start, last.start), Math.max(first.end, last.end));
            }
            if (last.start <= first.end) return null;
            const parts = [];
            parts.push(startWhole ? slice(first.start, first.end) : selectedTextWithin(range, startBlock));
            if (last.start > first.end + 1) parts.push(slice(first.end + 1, last.start - 1));
            parts.push(endWhole ? slice(last.start, last.end) : selectedTextWithin(range, endBlock));
            return parts.join('\\n');
        }

        function plainTextFromFragment(fragment) {
            const div = document.createElement('div');
            div.appendChild(fragment.cloneNode(true));
            return div.innerText || div.textContent || '';
        }

        function htmlFromFragment(fragment) {
            const div = document.createElement('div');
            div.appendChild(fragment.cloneNode(true));
            return div.innerHTML;
        }

        async function copyCodeBlock(button) {
            const wrap = button.closest('.md-code-wrap');
            const code = wrap && wrap.querySelector('pre > code');
            if (!code) return;
            const text = code.textContent || '';
            let copied = false;
            try {
                copied = post({ kind: 'copyCode', value: text });
            } catch (e) {}
            // Quick Look has no host bridge; it registers a dedicated
            // pasteboard handler instead (see belvedere-quick-look/PreviewViewController).
            if (!copied) {
                try {
                    const handler = window.webkit?.messageHandlers?.mdPreviewCopyCode;
                    if (handler) {
                        handler.postMessage(text);
                        copied = true;
                    }
                } catch (e) {}
            }
            if (!copied && navigator.clipboard && navigator.clipboard.writeText) {
                try {
                    await navigator.clipboard.writeText(text);
                    copied = true;
                } catch (e) {}
            }
            if (!copied) {
                // Last resort for non-secure contexts: execCommand works
                // from a user gesture without clipboard permissions.
                try {
                    const selection = getSelection();
                    const saved = selection && selection.rangeCount
                        ? selection.getRangeAt(0).cloneRange() : null;
                    const range = document.createRange();
                    range.selectNodeContents(code);
                    selection.removeAllRanges();
                    selection.addRange(range);
                    copied = document.execCommand('copy');
                    selection.removeAllRanges();
                    if (saved) selection.addRange(saved);
                } catch (e) {}
            }
            if (!copied) return;
            button.innerHTML = codeIcon('check');
            button.title = localized.codeCopied;
            button.setAttribute('aria-label', localized.codeCopied);
            button.classList.add('is-copied');
            clearTimeout(button.__mdCopyTimer);
            button.__mdCopyTimer = setTimeout(() => {
                button.innerHTML = codeIcon('copy');
                button.title = localized.copyCode;
                button.setAttribute('aria-label', localized.copyCode);
                button.classList.remove('is-copied');
            }, 1100);
        }

        document.addEventListener('click', (event) => {
            const toggle = event.target.closest('.md-code-toggle-wrap');
            if (toggle) {
                event.preventDefault();
                event.stopPropagation();
                const wrapped = toggle.closest('.md-code-wrap').classList.toggle('is-wrapped');
                toggle.setAttribute('aria-pressed', String(wrapped));
                toggle.title = wrapped ? localized.unwrapCode : localized.wrapCode;
                toggle.setAttribute('aria-label', toggle.title);
                toggle.innerHTML = codeIcon(wrapped ? 'unwrap' : 'wrap');
                return;
            }
            const button = event.target.closest('.md-code-copy');
            if (!button) return;
            event.preventDefault();
            event.stopPropagation();
            copyCodeBlock(button);
        });

        // Registered on window so it runs after every document-level copy
        // handler, including the math copy helper that rewrites the plain
        // text of selections containing formulas; the Markdown source
        // already carries the formula source, so it wins when available.
        window.addEventListener('copy', (event) => {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || !event.clipboardData) return;
            const { fragment, removedButtons } = selectionFragment(selection);
            const markdown = markdownForSelection(selection);
            if (markdown !== null) {
                event.clipboardData.setData('text/plain', markdown);
                event.clipboardData.setData('text/html', htmlFromFragment(fragment));
                event.preventDefault();
                return;
            }
            // Another handler already wrote the pasteboard: leave it alone.
            if (event.defaultPrevented) return;
            // Otherwise only step in to keep code copy buttons out of the text.
            if (!removedButtons) return;
            event.clipboardData.setData('text/plain', plainTextFromFragment(fragment));
            event.clipboardData.setData('text/html', htmlFromFragment(fragment));
            event.preventDefault();
        });

        // Vendor lazy-load helpers. rAF is paused while the WKWebView is
        // offscreen (e.g. during the launch-time warmup before the window
        // becomes visible), so afterPaint also falls back to setTimeout(50).
        window.MdPreviewLazy = {
            afterPaint(cb) {
                function tick() {
                    let fired = false;
                    function fire(via) {
                        if (!fired) {
                            fired = true;
                            perfLog('afterPaint fire', via);
                            cb();
                        }
                    }
                    requestAnimationFrame(() => requestAnimationFrame(() => fire('rAF')));
                    setTimeout(() => fire('timeout'), 50);
                }
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', tick, { once: true });
                } else {
                    tick();
                }
            },
            loadScript(src) {
                return new Promise((resolve, reject) => {
                    const tStart = perfNow();
                    perfLog('script append', src);
                    const s = document.createElement('script');
                    s.onload = () => {
                        perfLog('script onload', src + ' (+' + (perfNow() - tStart).toFixed(1) + 'ms)');
                        resolve();
                    };
                    s.onerror = () => reject(new Error('failed: ' + src));
                    s.src = src;
                    document.head.appendChild(s);
                });
            },
            // Wires up a renderer whose vendor JS is loaded after first paint.
            // - registers a reapplier that gates on `loaded`, so fast-path
            //   updates don't fire the renderer before its bundle has arrived
            // - on first paint, fetches `src` (and any `extras` after) and
            //   calls `run`
            lazyRenderer({ src, extras, run }) {
                let loaded = false;
                let firstRunDone;
                this.firstRuns.push(new Promise(resolve => { firstRunDone = resolve; }));
                if (window.MdPreview && window.MdPreview.registerReapplier) {
                    window.MdPreview.registerReapplier(() => { if (loaded) run(); });
                }
                this.afterPaint(async () => {
                    try {
                        await this.loadScript(src);
                        loaded = true;
                        await run();
                        if (extras) {
                            for (const e of extras) this.loadScript(e).catch(() => {});
                        }
                    } catch (e) {
                    } finally {
                        firstRunDone();
                    }
                });
            },
            // One promise per lazy renderer, settled once it has loaded and
            // run, or failed. Printing and export copy the page and strip its
            // scripts, so math or highlighting that had not run by then would
            // stay raw source in the copy for good. They wait for this first.
            firstRuns: [],
            settled() {
                return Promise.allSettled(this.firstRuns);
            }
        };

        // DOMPurify config. Closes the raw-HTML XSS path on user markdown
        // (EscapingHTMLFormatter passes block- and inline-HTML through per
        // CommonMark). Inline event handlers, <script>, <iframe>, <object>,
        // <embed>, <base>, <meta>, <link>, <style>, and <form> are dropped;
        // the `style` attribute is stripped to defeat visual-deception
        // attacks against the copy button (display:none segments inside
        // <pre><code> would otherwise survive into clipboard textContent).
        // <button> stays allowed so the mermaid zoom HUD survives sanitize();
        // without a parent <form> (forbidden above), `formaction` has nothing
        // to submit to, and on* handlers are stripped by DOMPurify defaults.
        //
        // ALLOWED_URI_REGEXP extends DOMPurify's default safe-URL list with
        // `md-asset:` so markdown image references that resolve to the
        // document's base directory (![alt](relative/path.png)) keep working.
        const SANITIZE_CONFIG = {
            // Forbidding 'form' alone is not enough. DOMPurify defaults to
            // KEEP_CONTENT: true, which unwraps a forbidden element and
            // reparents its children -- so <form><input><button></form> lost
            // the form and kept a text field and a submit button, and a
            // document could draw a credential prompt. Counting <form> made
            // that look sanitized; the controls are what the reader sees.
            // `button` is deliberately NOT forbidden. MarkdownHTML+Mermaid
            // emits the five HUD controls (zoom out, reset, zoom in, fill
            // width, open in window) as part of the article HTML, so they pass
            // through this sanitiser like any other markup. Forbidding the tag
            // removed all five, which shipped in 1.0.4 and 1.0.5 before it was
            // caught. Distinguishing app buttons from document ones by class
            // would not do either: the class is author-supplied, so it cannot
            // be a security exception. The tags below are the ones the
            // renderer never emits -- verified, not assumed.
            FORBID_TAGS: ['style', 'form', 'iframe', 'object',
                          'embed', 'meta', 'link', 'base',
                          'select', 'textarea', 'option', 'optgroup',
                          'fieldset', 'legend', 'label', 'datalist', 'output'],
            // `command` and `commandfor` let a button open a dialog as a
            // modal, which covers the page and makes the rest of it inert,
            // with no script. DOMPurify 3.4.2 dropped them; later 3.4.x
            // releases allow them by default, so they are forbidden here to
            // keep the surface the reader had. `data-md-app` marks the app's
            // own table controls (see decorateTables); a document may not
            // claim it.
            FORBID_ATTR: ['style', 'command', 'commandfor', 'data-md-app'],
            ADD_ATTR: ['target'],
            ALLOWED_URI_REGEXP: /^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix|md-asset):|[^a-z]|[a-z+.\\-]+(?:[^a-z+.\\-:]|$))/i
        };
        // <input> cannot simply be forbidden: EscapingHTMLFormatter emits one
        // per task-list item. Allow exactly that shape and drop every other
        // input: a text or password field is what invites typing, and a bare
        // button without one is not worth breaking the Mermaid HUD for.
        //
        // Two traps here, both hit while writing this:
        //
        // 1. The hook must be installed for BOTH sanitize paths. The morphdom
        //    update path calls DOMPurify.sanitize directly with
        //    SANITIZE_DOM_CONFIG rather than going through sanitize() below,
        //    so a hook installed only there covers the cold render and leaves
        //    the hot path -- every file change and editor exit -- unhardened.
        //    DOMPurify hooks are global, so installing once covers both.
        //
        // 2. The rule must not require `disabled`. The renderer emits
        //    `disabled=""` on task checkboxes and DOMPurify *preserves* it.
        //    An earlier version of this comment said DOMPurify strips the
        //    attribute; that was wrong, and the error came from reading the
        //    final DOM without asking what else had touched it. Task
        //    checkboxes stay `disabled` in every surface now: the reading
        //    view is read-only, and ticking a task is done in Edit Mode. (An
        //    earlier upstream `enableTaskCheckboxes()` re-enabled them in the
        //    app window; if anything like it returns, the rule above must
        //    still not depend on `disabled`.)
        let sanitizerHooked = false;
        function configureSanitizer() {
            if (sanitizerHooked || typeof DOMPurify === 'undefined' || !DOMPurify.addHook) return;
            sanitizerHooked = true;
            DOMPurify.addHook('uponSanitizeElement', (node, data) => {
                if (data.tagName !== 'input') return;
                const type = (node.getAttribute && node.getAttribute('type') || '').toLowerCase();
                if (type !== 'checkbox' && node.parentNode) {
                    node.parentNode.removeChild(node);
                }
            });
        }

        function sanitize(html) {
            if (typeof html !== 'string') return '';
            if (typeof DOMPurify === 'undefined' || !DOMPurify.sanitize) {
                // Fail closed: refuse to render rather than risk shipping
                // unsanitized HTML into innerHTML. This branch fires only if
                // the bundled purify.min.js is missing from the app bundle.
                if (window.console && console.error) {
                    console.error('[belvedere] DOMPurify not loaded; refusing to render article.');
                }
                return '';
            }
            configureSanitizer();
            return DOMPurify.sanitize(html, SANITIZE_CONFIG);
        }

        // Incremental-update entry point. Each renderer (KaTeX/Mermaid)
        // registers an idempotent reapplier that re-processes the current
        // article. Same-flag re-renders skip the WKWebView reload entirely.
        const reappliers = [];
        window.MdPreview = window.MdPreview || {};
        window.MdPreview.registerReapplier = (fn) => {
            if (typeof fn === 'function') reappliers.push(fn);
        };
        function mdHash(s) {
            let h = 5381;
            for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
            return h.toString(36);
        }

        // One row per expensive block kind: the wrapper class, a key prefix,
        // where the node carrying __mdSrc and the renderer's done flag lives
        // inside the wrapper (null = the wrapper itself), and where the
        // source-position attrs live when not on the wrapper. The keying,
        // preservation, and attr-sync helpers below all derive from this
        // table, so a new renderer means one new row — not three new branches.
        const EXPENSIVE_BLOCKS = [
            { cls: 'mermaid-figure', kind: 'mm',   inner: '.mermaid',   done: 'mmDone',   attrInner: null  },
            { cls: 'md-code-wrap',   kind: 'code', inner: 'pre > code', done: 'hljsDone', attrInner: 'pre' },
            { cls: 'math',           kind: 'math', inner: null,         done: 'mathDone', attrInner: null  }
        ];
        const EXPENSIVE_SELECTOR = EXPENSIVE_BLOCKS.map((b) => '.' + b.cls).join(', ');
        function expensiveKindOf(el) {
            if (!el.classList) return null;
            return EXPENSIVE_BLOCKS.find((b) => el.classList.contains(b.cls)) || null;
        }
        function expensiveSrcNode(el, info) {
            return info.inner ? el.querySelector(info.inner) : el;
        }

        // Content-derived keys so morphdom re-pairs unchanged diagrams/math/
        // code even when blocks are inserted above them. Live nodes hash the
        // stashed __mdSrc (renderers replace textContent with their output);
        // incoming nodes hash textContent — the same Swift emitter produced
        // both strings, so identical source yields identical keys.
        function keyExpensiveBlocks(root) {
            const counts = new Map();
            root.querySelectorAll(EXPENSIVE_SELECTOR).forEach((el) => {
                const info = expensiveKindOf(el);
                const srcNode = expensiveSrcNode(el, info);
                if (!srcNode) return;
                const src = srcNode.__mdSrc !== undefined ? srcNode.__mdSrc : srcNode.textContent;
                // Hash memoized per node — live-tree sources are stable
                // across updates, so only fresh incoming nodes pay the hash.
                // Kind-prefixed so a hash collision can never pair blocks of
                // different types (block math and code wraps are both <div>s).
                let base = srcNode.__mdKeyBase;
                if (base === undefined || srcNode.__mdKeySrc !== src) {
                    base = info.kind + '-' + mdHash(src);
                    srcNode.__mdKeyBase = base;
                    srcNode.__mdKeySrc = src;
                }
                const n = (counts.get(base) || 0) + 1;
                counts.set(base, n);
                el.setAttribute('data-md-key', 'k' + base + ':' + n);
            });
        }

        // A preserved subtree keeps its pre-shift source metadata, which
        // would desync scroll handoff and table edits after lines move.
        // Copy the incoming line attributes onto the live node.
        function syncSourceAttrs(fromEl, toEl, info) {
            let from = fromEl;
            let to = toEl;
            if (info.attrInner) {
                from = fromEl.querySelector(info.attrInner);
                to = toEl.querySelector(info.attrInner);
                if (!from || !to) return;
            }
            for (const name of ['data-source-line', 'data-source-start', 'data-source-end']) {
                const value = to.getAttribute(name);
                if (value === null) from.removeAttribute(name);
                else from.setAttribute(name, value);
            }
        }

        // True when the live subtree holds finished renderer output for the
        // exact source the incoming node carries — morphdom must then leave
        // it untouched. Anything else (still rendering, changed source)
        // morphs normally and the reappliers re-render it.
        function isRenderedForSource(info, fromEl, toEl) {
            const live = expensiveSrcNode(fromEl, info);
            const incoming = expensiveSrcNode(toEl, info);
            return !!live && !!incoming && live.dataset[info.done] === '1'
                && live.__mdSrc === incoming.textContent;
        }

        // Both are stateless, so they're built once instead of per update —
        // MdPreview.update is the per-keystroke-exit/file-change hot path.
        const SANITIZE_DOM_CONFIG = Object.assign({}, SANITIZE_CONFIG, { RETURN_DOM_FRAGMENT: true });
        const MORPH_OPTIONS = {
            childrenOnly: true,
            getNodeKey: (node) => node.nodeType === 1
                ? (node.getAttribute('data-md-key') || node.id || undefined)
                : undefined,
            onBeforeElUpdated: (fromEl, toEl) => {
                if (fromEl.isEqualNode(toEl)) return false;
                // Skipping is all-or-nothing per subtree: letting morphdom
                // descend would strip the done markers (incoming nodes lack
                // them) and force a destructive re-render on the next reapply.
                const info = expensiveKindOf(fromEl);
                if (info && isRenderedForSource(info, fromEl, toEl)) {
                    syncSourceAttrs(fromEl, toEl, info);
                    return false;
                }
                // Keep the reader's open/closed choice, unless the source
                // changed a callout's fold marker (`[!faq]-` to `[!faq]+`).
                if (fromEl.tagName === 'DETAILS'
                    && fromEl.getAttribute('data-md-fold') === toEl.getAttribute('data-md-fold')) {
                    toEl.toggleAttribute('open', fromEl.open);
                }
                return true;
            }
        };

        // `opts.keepHidden` preserves the warmup opacity so the synthetic
        // Mermaid pre-render doesn't flash on screen. The host then issues a
        // second update without the flag once the real document arrives,
        // which clears the inline style and reveals the article.
        window.MdPreview.markdownForSelection = markdownForSelection;
        window.MdPreview.plainTextForSelection = plainTextForSelection;
        window.MdPreview.clearColumnResize = clearColumnResize;

        window.MdPreview.update = (articleHTML, opts) => {
            // The Markdown behind the article, for copy-as-source.
            if (opts && typeof opts.source === 'string') {
                window.MdPreview.source = opts.source;
            }
            // Body swaps can carry a document from a different folder — move
            // the page <base> first so the incoming content's relative URLs
            // resolve against the right folder.
            if (opts && opts.baseHref) {
                const base = document.querySelector('base');
                if (base && base.getAttribute('href') !== opts.baseHref) {
                    base.setAttribute('href', opts.baseHref);
                }
            }
            const article = document.querySelector('.markdown-body');
            if (!article) return;
            // A document swap invalidates any selection from the old article.
            if (lastSelectedText !== null) {
                lastSelectedText = null;
                post({ kind: 'selectedText', value: null });
            }
            const tStart = perfNow();
            // DOM-diff fast path: morph the live article toward the incoming
            // HTML so finished Mermaid SVGs, KaTeX output, and highlighted
            // code survive the update instead of being re-rendered. Skipped
            // for the first populate (empty article), the warmup article,
            // and whenever morphdom or DOMPurify is missing; any throw
            // falls back to the innerHTML swap below.
            const canMorph = !!articleHTML && article.firstElementChild
                && article.dataset.warmup !== '1'
                && typeof morphdom === 'function'
                && typeof DOMPurify !== 'undefined' && DOMPurify.sanitize;
            let morphed = false;
            if (canMorph) {
                try {
                    configureSanitizer();
                    const frag = DOMPurify.sanitize(articleHTML, SANITIZE_DOM_CONFIG);
                    const next = document.createElement('article');
                    next.appendChild(frag);
                    // Pre-shape the incoming tree so the decorators' wrappers
                    // pair one-to-one with the live DOM during the diff.
                    decorateCodeBlocks(next);
                    decorateTables(next);
                    keyExpensiveBlocks(article);
                    keyExpensiveBlocks(next);
                    morphdom(article, next, MORPH_OPTIONS);
                    // Deferral has to run on the live tree, after the diff.
                    // Images in the detached `next` never load, so no error
                    // ever fires there, and morphdom would replace the nodes
                    // the listeners were attached to anyway.
                    deferBlockedImages(article);
                    morphed = true;
                } catch (e) {
                    perfLog('morphdom fallback', String(e && e.message || e));
                }
            }
            if (!morphed) {
                article.innerHTML = sanitize(articleHTML);
            }
            if (!opts || !opts.keepHidden) {
                article.style.opacity = '';
                article.style.pointerEvents = '';
                // Revealing means the synthetic warmup content is gone — the
                // hidden populate keeps the flag so the first real document
                // still takes the guaranteed innerHTML replace above, and
                // every update after it may morph.
                delete article.dataset.warmup;
            }
            if (articleHTML) {
                // The morph path already decorated the incoming tree; only
                // the innerHTML swap leaves fresh undecorated nodes behind.
                if (!morphed) {
                    decorateCodeBlocks();
                    decorateTables();
                    deferBlockedImages();
                }
                for (const fn of reappliers) {
                    try { fn(); } catch (e) { /* one bad apple shouldn't block others */ }
                }
            }
            // Morphing can preserve a native selection without a selectionchange event.
            // Re-report it after the DOM update if it still intersects the article.
            pushSelectedText();
            perfLog('MdPreview.update' + (morphed ? ' (morphdom)' : ''), '(+' + (perfNow() - tStart).toFixed(1) + 'ms)');
            pushHeight();
        };

        // Initial-load populator. The article body ships inside an inert
        // <template> element so the parser never fires inline event handlers
        // on first paint. Pull it out, sanitize, inject. The template is
        // removed once consumed.
        function populateFromTemplate() {
            const tmpl = document.getElementById('md-article-source');
            if (!tmpl) return;
            const article = document.querySelector('.markdown-body');
            const keepHidden = !!(article && article.dataset.warmup === '1');
            window.MdPreview.update(tmpl.innerHTML, { keepHidden });
            tmpl.remove();
        }
        // Body-end hook: inline-mode documents call this right after the
        // template parses, before the vendor bundles, so text paints early.
        window.MdPreview.populateNow = populateFromTemplate;

        function start() {
            perfLog('start (DOM ready)');
            populateFromTemplate();
            decorateCodeBlocks();
            decorateTables();
            // No deferBlockedImages() here: populateFromTemplate routes through
            // MdPreview.update, which defers. A second call would be dead code
            // whose rationale reads as a real requirement.
            // testInitialPageRenderDefersOnItsOwn guards the outcome rather
            // than this arrangement, so rerouting populate is free to change it.
            pushHeight();
            try {
                const ro = new ResizeObserver(pushHeight);
                ro.observe(document.body);
                const article = document.querySelector('.markdown-body');
                if (article) ro.observe(article);
            } catch (e) {}
            window.addEventListener('belvedere-mermaid-rendered', pushHeight);
            window.addEventListener('belvedere-math-rendered', pushHeight);
            window.addEventListener('load', pushHeight);
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', start, { once: true });
        } else {
            start();
        }
    })();
    </script>
    """
}
