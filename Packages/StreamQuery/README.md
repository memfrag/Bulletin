# StreamQuery

The query language behind saved streams.

A stream is a saved predicate, evaluated live every time it is viewed. This
package is that predicate: its syntax tree, the text form users type, the row
form the rule builder edits, and the SQL it compiles to.

```
unread folder:Dev -tag:noise title:swift after:7d
```

## The round-trip rule

The rule builder is the primary editor and the text form is what it displays.
Both must survive conversion in either direction:

```
rows → text → parse → rows        must be the identity
```

That constraint **defines the grammar**. Anything that cannot round-trip
losslessly is not in the language, however useful it might have been. The
property test in `RoundTripTests` is the specification.

## Layout

| File | What it is |
|---|---|
| `QueryExpression.swift` | The syntax tree, and its normal form |
| `QueryLexer.swift` | Text → tokens |
| `QueryParser.swift` | Tokens → tree |
| `QuerySerializer.swift` | Tree → text |
| `QueryBuilderRows.swift` | Tree ⇄ the rule builder's flat rows |
| `QuerySQLCompiler.swift` | Tree → a SQL `WHERE` clause plus bindings |

Nothing here executes SQL — it emits it, so the compiler can be tested on its
output rather than on a database.
