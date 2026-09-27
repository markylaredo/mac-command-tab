# Window search benchmark

Differential evaluation harness for MacCommandTab's window search. It answers one
question: **what changed when token-coverage recall was added, and where does the
search still fall short?**

It performs no network I/O, needs no API key, and modifies nothing in the app
target.

## Running it

```sh
./Benchmarks/run.sh
```

The script compiles `MacCommandTab/Switcher/WindowSearch.swift` and
`MacCommandTab/Windows/WindowInfo.swift` **directly from the app target** and
links them with the fixtures and the harness in this directory. Nothing is
copied, so the benchmark cannot silently drift away from shipped behaviour. The
Xcode project is not involved and the app is not rebuilt.

Fixture windows never construct a real accessibility element, so no Accessibility
or Screen Recording permission is required.

## How it works

`LiteralWindowSearch` in `main.swift` reproduces the previous whole-query-only
matcher, for evaluation purposes only. Every query runs through both
implementations and each result is classified:

| Classification | Meaning |
| --- | --- |
| unchanged | Identical results **and** identical order. |
| recall gained | Previously empty, now populated. |
| still empty | Nothing from either implementation. |
| regression | Results lost, or the previous order not preserved. |

Whole-query matches are authoritative, so when the baseline produced results the
new implementation must keep them and may only append. Anything else is a
regression. The regression count must be zero.

## Window sets

| Set | Shape | Windows |
| --- | --- | --- |
| A | Multi-project web development | 10 |
| B | Many windows, several browsers | 14 |
| C | Accounting and office work | 7 |
| D | Small session | 4 |
| E | Stress test — windows sharing vocabulary | 40 |

Set order is MRU order, which matters: ranking ties preserve input order.

## Current results

Measured on the development Mac, arm64, `-O`, Swift 6.
`WindowSearch.filter`, 200 iterations per query.

### Differential

38 evaluations:

| Outcome | Count |
| --- | --- |
| unchanged (identical results and order) | 22 |
| recall gained | 3 |
| regressions | **0** |
| still empty | 13 |
| fixture errors | 0 |

**Recall gained:**

| Query | Set | Before | After |
| --- | --- | --- | --- |
| `OMECO Rider` | A | 0 results | 2 — Rider "Omeco.ApiV2" first |
| `OMECO Rider` | B | 0 results | 1 — Rider "Omeco.ApiV2" |
| `Finder downloads` | B | 0 results | 1 — Finder "Downloads" |

No query lost results and no ordering changed.

### Still empty

13 evaluations return nothing from either implementation. Deduplicated by
query, these are the cases no string comparison reaches:

| Query | Intended window | Why it stays empty |
| --- | --- | --- |
| `VS Code FleetShell` | VS Code — `fleet-shell` | "VS Code" is an abbreviation of "Visual Studio Code". The title does contain `fleet-shell`, but the app name contains no `vs` token, and every token must match. |
| `my terminal` | Terminal | "my" appears in no window. |
| `browser with GitHub` | Chrome — "GitHub · Pull requests" | "browser" is a category and "with" is a stopword; every-token matching rejects the window on both. |
| `accounting project` | Numbers — "Ledger 2026 — Q1" | Disjoint vocabulary. |
| `settings for displays` | System Settings — "Displays" | Intent phrasing vs a bare noun. |
| `Chrome docs` | Safari — "Apple Developer Documentation" | "docs" appears nowhere. |

Each of these has an **empty shortlist**, which is why a re-ranker cannot reach
any of them. See "What this means for TypeSafe" below.

### Latency

Widening runs only when whole-query matching finds nothing, so the common path is
unchanged. The widening path costs roughly 2–3× a single-character query and
stays in the tens to low hundreds of microseconds.

| Set | Windows | single-char p50 | widening p50 | widening p95 |
| --- | --- | --- | --- | --- |
| A | 10 | 14.5 µs | 37.7 µs | 39.6 µs |
| B | 14 | 18.8 µs | 52.8 µs | 53.8 µs |
| C | 7 | 8.3 µs | 21.9 µs | 22.4 µs |
| D | 4 | 5.6 µs | 14.2 µs | 14.6 µs |
| E | 40 | 50.4 µs | 152.7 µs | 162.0 µs |

Set E is the stress case: 40 windows, worst case 0.16 ms. The entire search still
costs well under a millisecond — three to four orders of magnitude below one
TypeSafe round trip.

### Recall widening probe

Set E holds 40 windows built to share vocabulary. Each probe below matches no
window literally, so it takes the widening path.

| Probe | Accepted | Flags |
| --- | --- | --- |
| `Terminal docker` | 10 / 40 | FLAT |
| `omeco api` | 10 / 40 | FLAT |
| `docker service` | 10 / 40 | FLAT |
| `GitHub service` | 0 / 40 | — |
| `chrome github service` | 0 / 40 | — |

`LARGE` means the widened set exceeded 25% of the session. `FLAT` means every
result was the same application.

**No query floods.** The every-token requirement keeps the widened set bounded
even in a large session full of shared vocabulary. The `FLAT` cases are a
discriminating-power limit, not a correctness problem: the windows returned are
genuinely relevant, the query simply does not distinguish between them. This is
not new behaviour either — a literal single-token query like `"Terminal"` already
returns every Terminal window. Adding tokens fixes it, which the three-token
probe demonstrates.

## The search behaviour under test

`WindowSearch` runs in two phases.

**Phase one — whole-query matching.** The six documented rank classes, applied to
the query as a whole. Unchanged and authoritative: a query that matches literally
is answered exactly as before.

**Phase two — token-coverage recall.** Reached only when phase one finds nothing
and the query has at least two whitespace-separated tokens. A window is accepted
when **every** token appears somewhere in its application name or window title,
and results are ordered by coverage, then by which field matched, then by MRU
position.

Phase two exists because the two fields are matched independently while a
multi-token query is a single string. `"OMECO Rider"` matches neither
`"Omeco.ApiV2 – Rider"` (the token `omeco` does not contain the whole query) nor
anything else, even though one window accounts for both tokens.

Requiring **every** token is what keeps recall bounded. Accepting a subset was
tried and rejected: it drags in any window sharing one common word with the query.

## What this means for TypeSafe

The remaining gap is now small, bounded, and precisely characterised. Of the
distinct empty queries, the survivors are those needing **world knowledge that is
not present in the window metadata at all**:

- `VS Code` → `Visual Studio Code` is an abbreviation expansion.
- `my terminal` → `Terminal` needs parsing past a possessive and a stopword.
- `browser with GitHub` → needs `browser` recognised as a category and `with`
  discarded as noise.
- `accounting project` → `Ledger 2026 — Q1` needs a synonym relationship.

These are genuine semantic judgments. They are also exactly the cases a
per-candidate re-ranker **cannot** reach, because the shortlist is empty before
ranking begins.

So the conclusion from the earlier evaluation is unchanged, and is now backed by
measurement rather than argument:

1. **Deterministic recall widening (done)** closed every case where the query's
   own words were present in the metadata. That was the majority of the gap, and
   it needed no model.
2. **What remains needs mapping between vocabularies**, not reordering a
   candidate list. A *shortlist-widening* step — deciding which windows are worth
   ranking at all — would have to come first. That is a different TypeSafe
   question ("could this window be what the user means?", asked against every
   window rather than a shortlist), it is a larger change, and it carries a larger
   privacy surface: it means transmitting the full window list.
3. The credential problem from the main evaluation is unaffected and still
   applies.

**Recommendation: stop here.** The deterministic fix delivered the measurable
win. The residual gap is real but narrow, and closing it requires the
full-window-list privacy tradeoff plus a distributed-credential solution that
does not currently exist for this app. Revisit only if the empty-query cases above
prove common in real use — which the app can now measure locally, without any
network access.

## Adding fixtures

- `WindowSearchFixtures.swift` — window sets. Keep them realistic; invented
  titles that are convenient for the matcher produce misleading results.
- `WindowSearchQueries.swift` — queries and expectations. Prefer `.derived` for
  bare-name queries so expectations stay set-relative, and `.noMatch` only when
  no window in the set matches literally. The harness enforces that rule.
