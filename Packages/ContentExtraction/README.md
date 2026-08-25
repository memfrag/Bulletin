# ContentExtraction

Turns a web page into the article that is on it.

Feeds that ship only a truncated summary are the normal case, not the exception,
so the reader needs to be able to go and get the rest. Two extractors, tried in
that order:

- **`HeuristicExtractor`** — `URLSession` plus [SwiftSoup](https://github.com/scinfu/SwiftSoup).
  Scores candidate elements by text density and link density and returns the
  winner. Cheap, no WebView, and fully testable against saved pages.
- **`ReadabilityExtractor`** — a headless `WKWebView` running Mozilla's
  [Readability](https://github.com/mozilla/readability). Loads the page for real,
  so it wins on JavaScript-rendered pages the heuristic extractor cannot see.

The heuristic one is the default attempt and Readability is the escalation,
because loading a page in a WebView runs the publisher's own scripts.

## Third-party

`Resources/Readability.js` is Mozilla's Readability 0.6.0, Apache 2.0 — see
`Resources/Readability-LICENSE.md`.
