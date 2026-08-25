# FeedIngest

Everything between a feed URL and a set of articles: fetching, parsing,
discovery, canonical URLs and OPML.

Deliberately knows nothing about SwiftData, CloudKit or SwiftUI. It takes bytes
and returns values, which is what makes it testable without launching an app.

## Formats

RSS 2.0, Atom and JSON Feed are parsed by [FeedKit](https://github.com/nmdias/FeedKit).
FeedKit 10 dropped RSS 1.0/RDF, so `RDFFeedParser` handles that format here.
`FeedParser` detects which of the four it is holding and dispatches accordingly.
