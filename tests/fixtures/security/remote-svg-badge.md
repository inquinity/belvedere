# Remote SVG badges

README badges from shields.io and similar services are SVG. They are remote
images like any other: nothing loads on open, and **Load** fetches one on a
click. The host checks that the bytes start like an SVG document and hands the
page a `data:` URL, which the page shows only as an `<img>`. WebKit runs no
script inside an SVG drawn as an image and loads nothing the SVG names.

Opening this document sends nothing. Clicking **Load** sends one request to
`img.shields.io`, which is a real host, so only click it when that is what you
mean to do.

## A badge inside centred HTML

> **EXPECT:** on open, two placeholders naming `img.shields.io`, each with
> **Load** in the app window and none in Quick Look. Clicking **Load** on
> either shows the badge in place.
> **FAIL IF:** a badge renders without a click, or a click ends in
> **load failed: not an image** (SVG refused as before).

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-FF6B35?style=flat-square&logo=opensourceinitiative&logoColor=white)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-FF612B?style=flat-square)](CONTRIBUTING.md)

</div>

## An SVG that tries to do more than draw

`hostile-badge.svg`, next to this file, carries an `onload` handler and a
`<script>` that would turn it red and rewrite its text. Serve this folder as
described in `hostile-svg-test.md`, and open that file to load it.

> **EXPECT:** after **Load**, a grey badge reading "inert", and exactly one GET
> in the server log.
> **FAIL IF:** the badge is red or reads "SCRIPT RAN". That means the SVG was
> shown as a document rather than drawn as an image. Do not wait for an alert:
> the app shows none, so its absence proves nothing.
> `DeferredImageRenderingTests` checks the same thing automatically.
