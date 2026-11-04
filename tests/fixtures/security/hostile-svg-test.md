# Hostile SVG badge

Click-to-load for an SVG that carries script. Serve this folder first, so the
whole check stays on the machine:

```bash
cd tests/fixtures/security && python3 -m http.server 8731 --bind 127.0.0.1
```

> **EXPECT:** on open, a placeholder naming `127.0.0.1` with **Load**, and no
> request in the server log. After **Load**, a grey badge reading "inert", and
> exactly one GET for `hostile-badge.svg` per click.
> **FAIL IF:** the badge is red or reads "SCRIPT RAN": the SVG was shown as a
> document rather than drawn as an image, and its script ran. Do not wait for
> an alert; the app shows none, so its absence proves nothing.

![](http://127.0.0.1:8731/hostile-badge.svg)

End of test.
