# Mermaid

Version: **12.3.0** (also recorded in `Mermaid-VERSION`).

`mermaid.min.js` and `LICENSE` are copied without modification from the official
[`mermaid@12.3.0` npm package](https://registry.npmjs.org/mermaid/-/mermaid-12.3.0.tgz)
(`dist/mermaid.min.js` and `LICENSE`). The package SHA-512 integrity is:

```
sha512-4113TdXeLAsMruJ79OpFL5O8+LTFXhQqZ260rF3tgUmiNAtRm4Uume04I+65PRN6yZ69J4f8rVYWW8zRk65UYw==
```

npm verified its registry signature and its build provenance.

`mermaid.min.js` is a single-file build that includes 79 other packages,
among them the ELK layout engine under the Eclipse Public License 2.0, and
code compiled into some of them from other projects (Guava and GWT's runtime
inside ELK, for example). `Mermaid-THIRD-PARTY-NOTICES.txt` holds their
license notices. `bin/make-mermaid-notices.py` writes it from the bundle's
source maps, a table of packages known to carry others inside them, and a
table of such compiled-in code, and stops if a bundled package depends on
something it neither found nor has a recorded reason to leave out. Run it
again after every update, and extend its tables when it stops.

The app and Quick Look use this same offline renderer. Mermaid 12 changed its
defaults to the ELK layout, the "neo" look, and wider minimum node widths with
tighter label wrapping. `MarkdownHTML.mermaidSharedConfig`, which the reading
view and the editor both use, sets `layout: 'dagre'`, `look: 'classic'`, no
minimum node width and a 200 px wrap, so diagrams keep the size and look they
had with Mermaid 11.15.
The block-arrow reproduction is `samples/mermaid-block-arrows.md`, covered by
`MermaidBlockArrowTests` using the production HTML in WebKit.
