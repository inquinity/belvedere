# Mermaid

Version: **12.3.0** (also recorded in `Mermaid-VERSION`).

`mermaid.min.js` and `LICENSE` are copied without modification from the official
[`mermaid@12.3.0` npm package](https://registry.npmjs.org/mermaid/-/mermaid-12.3.0.tgz)
(`dist/mermaid.min.js` and `LICENSE`). The package SHA-512 integrity is:

```
sha512-4113TdXeLAsMruJ79OpFL5O8+LTFXhQqZ260rF3tgUmiNAtRm4Uume04I+65PRN6yZ69J4f8rVYWW8zRk65UYw==
```

npm verified its registry signature and its build provenance.

`mermaid.min.js` is a single-file build that includes Mermaid's dependencies,
among them the ELK layout engine under the Eclipse Public License 2.0.
`Mermaid-THIRD-PARTY-NOTICES.txt` holds each one's license notice, at the
versions Mermaid's lockfile pinned for this release. It is written by
`bin/make-mermaid-notices.py`; run it again after an update.

The app and Quick Look use this same offline renderer. Mermaid 12 changed its
defaults to the ELK layout and the "neo" look; Belvedere sets `layout: 'dagre'`
and `look: 'classic'` (`MarkdownHTML+Mermaid.swift`, `EditorHTML.swift`) so
diagrams look as they did with Mermaid 11 and as they do on GitHub.
The block-arrow reproduction is `samples/mermaid-block-arrows.md`, covered by
`MermaidBlockArrowTests` using the production HTML in WebKit.
