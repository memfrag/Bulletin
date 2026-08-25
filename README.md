
# Bulletin

A macOS RSS reader whose sidebar is made of queries you wrote rather than
folders you filed things into.

It fetches feeds itself — no service account, no server. Subscriptions and
reading state sync between your Macs over iCloud; article text stays on the
machine that fetched it.

## What it does

- **Streams.** A stream is a saved query, evaluated live every time you look at
  it: `unread folder:Dev -tag:noise title:swift after:7d`. Build it from rows or
  type it; both are views of the same thing. Nothing is ever filed or mutated to
  make a stream match.
- **Reads truncated feeds properly.** Four text sources per article — the feed's
  own text, a fast native extractor, Mozilla Readability in a headless web view,
  or the live page. The choice sticks to the feed, so a feed that always
  truncates needs fixing once.
- **Search over everything**, including article bodies, through an FTS5 index.
- **Collapses duplicates** — the same story from five feeds is one row.
- **Keyboard-first**, with every action also in a menu.
- Nested folders, article tags, notes, OPML in and out, and a Feed Health view
  for feeds that have quietly stopped working.

## Building

Open `Bulletin.xcodeproj` and run the **Bulletin (Debug)** scheme. Debug signs
ad-hoc, so it needs no team and no provisioning profile.

```sh
xcodebuild -project Bulletin.xcodeproj -scheme "Bulletin (Debug)" -destination 'platform=macOS' test
```

The packages under `Packages/` test on their own and are the faster loop:

```sh
cd Packages/StreamQuery && swift test
```

| Package | What it is |
|---|---|
| `StreamQuery` | The query language: tree, parser, serializer, builder bridge, SQL compiler. No I/O, no dependencies. |
| `FeedIngest` | Fetching and parsing RSS 2.0, Atom, JSON Feed and RSS 1.0/RDF; discovery; OPML. |
| `ContentExtraction` | Getting the article off a web page, two ways. |
| `AppDesign` | The design system. |

## Releasing

```sh
./scripts/build-and-notarize.sh
```

Archives, signs with Developer ID, builds a DMG, notarizes, staples, signs for
Sparkle, publishes a GitHub release and updates `appcast.xml`. It needs a `git`
remote, the `gh` CLI, and notarization credentials stored as the keychain
profile `notary`.

## Sync

Not switched on yet — it needs a registered CloudKit container. The schema is
already written to CloudKit's rules and a test suite enforces that.
See [Docs/CLOUDKIT.md](Docs/CLOUDKIT.md).

## License

See the LICENSE file for licensing information.
