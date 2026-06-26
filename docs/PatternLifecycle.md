# The License Pattern Life Cycle

This is a plain-language guide to how license detection works in Cavil and, in particular, what happens to a piece of
text from the moment Cavil first notices it to the moment it becomes a reusable rule. It is written for the people who
do the legal review — you do **not** need to be an engineer to read it. (If you *are* after the technical internals,
see the "Pattern Matching" section of [Architecture.md](Architecture.md).)

## The one idea to take away

Cavil never decides on its own that a piece of text is a license. It only ever **recognises text it has been taught to
recognise**. Each thing it has been taught is called a **pattern**. The whole job of legal review is, over time, to
teach Cavil good patterns — so that the next package that contains the same license text is understood automatically.

A pattern is just "this wording means this license, at this risk level". Once a pattern exists, every future package
that contains matching wording is resolved without anyone having to look at it again. That is why the patterns are
worth getting right: each one pays off forever.

Folding (described later) does not change this in spirit: when Cavil resolves a snippet automatically, it is still only
ever matching text to a license it already knows — it never invents a new one. The only difference is that it can act on
a *close, confident* match, not just an exact one, to spare you re-confirming the obvious.

## Where unresolved text comes from

When Cavil scans a package it does two kinds of matching:

- **License patterns** — wording it already recognises as a specific license (for example MIT or GPL-2.0-or-later).
  These resolve cleanly and need no attention.
- **Keyword patterns** — broad tripwires for words that *often* appear in legal text ("warranty", "redistribute",
  "permission is granted", and so on). These do **not** identify a license. They simply say "there might be something
  legal here, please look".

Each keyword hit captures the surrounding lines into a **snippet** — a small excerpt for a human (or an AI assistant)
to judge. Keyword matching is deliberately over-eager: roughly four out of five snippets turn out to be nothing
(a code comment, a log line, a package description). Sifting them is the day-to-day work, and it is exactly why
AI assistance is useful here.

## The four things that can happen to a snippet

Every snippet a person looks at ends up in one of four states (Cavil also resolves some on its own before they ever
reach you — see the next section). Three of these are decisions someone makes; the fourth happens by itself.

1. **It becomes a license pattern.** The snippet really is a license declaration. Someone trims it down to the
   reusable legal wording and saves it as a new pattern, tagged with the license name and a risk level. From then on
   that wording is recognised everywhere.
2. **It gets ignored.** The snippet is definitely *not* a license — a log message, a comment, test data. It is
   suppressed so it never clutters a queue again. Ignoring works at two granularities: a single snippet (by its
   content), or a whole file or folder at once (by a file-path **glob**, e.g. test fixtures or bundled
   license-reference data that should never have been scanned).
3. **It is reported as a missing license.** The snippet clearly *is* legally relevant, but it cannot be turned into a
   clean pattern on the spot — the boundaries are unclear, it is unusual custom wording, or it genuinely needs a
   lawyer's judgement. Rather than guess, it is parked on the **Missing Licenses** queue for an expert to handle.
4. **It is resolved automatically.** Once a new pattern is created, Cavil re-examines the affected packages. Any other
   snippet whose wording the new pattern now covers simply disappears — no one has to touch the duplicates.

## When Cavil resolves a snippet on its own

Most snippets are noise, and a lot of it is the *same* noise or the same well-known license wording over and over. To
keep those out of your queue, Cavil can resolve some snippets automatically, without anyone writing a pattern. You will
see two kinds, both labelled in the file view:

- **Folded** — the snippet is confidently the same as a license Cavil already knows, so it treats it as that license
  (writing a near-duplicate pattern would add nothing).
- **Cleared** — the snippet is recognisable license boilerplate, or a real license match right next to it already says
  everything, so it carries no new information and is set aside as noise without recording any license.

This is deliberately cautious: Cavil only does it when very confident, never for higher-risk licenses, and it never
invents a license — folding only ever points at one Cavil already recognises. It is also fully reversible. If a call
looks wrong, open the file, find the folded or cleared lines (marked in the source), and correct it in one step — write
a proper pattern, ignore it, or mark it as not legal text. The point is to shrink the pile of obvious cases so your
attention goes to the snippets that genuinely need a person.

(How Cavil makes this call is in the "Pattern Matching" section of [Architecture.md](Architecture.md).)

## Who proposes what

Two kinds of contributor feed the review queues, and **neither of them changes a report directly**. They only ever
make *proposals* that an administrator or lawyer later accepts or rejects:

- **Human contributors** working through the Cavil web interface.
- **AI assistants** connected through Cavil's tools. An AI can propose a new license pattern, propose ignoring a
  snippet or a file glob, and — completing the picture — **report a missing license** when it has found genuine legal
  text it is not confident enough to pattern itself. Anything an AI proposes is clearly marked with an
  "AI assisted" badge and carries a short reason, so you always know where a proposal came from and why.

The AI assistants follow a detailed instruction sheet (an "agent skill"). That sheet is written for the AI and is not
meant to be read by people — this document is its human-facing counterpart.

## The two pages you work from

Almost all of your reviewing happens on two pages.

### Change Proposals (`/licenses/proposed`)

The queue of proposed patterns, proposed snippet-ignores, and proposed file globs. Each entry shows the snippet (or
glob), who proposed it, the "AI assisted" badge and reason where applicable, and the closest existing pattern for
comparison. For each one you either **Accept** (Cavil applies it and schedules a re-scan of the affected packages) or
**Reject** (it is discarded). The edits needed here are usually light — confirm the license name, risk, and any
flags.

### Missing Licenses (`/licenses/missing`)

The queue of snippets reported as containing a license that nobody has patterned yet. **This is where the real
pattern-authoring happens**, so this page gives you the full pattern editor inline. For each report you can:

- See the snippet, the reporter, the "AI assisted" badge, and the reason it was flagged.
- Click **Edit Pattern** to open the full editor right there in the page — the same editor used everywhere else,
  with the snippet pre-loaded, the "smart edit" trimming helper, license name auto-complete (which also predicts the
  risk), and a "closest match" tab that shows the most similar existing pattern.
- Trim the snippet to its reusable legal core, choose the license and risk, and **Create Pattern**. Cavil checks the
  pattern still matches the snippet, saves it, removes the report from the queue, and re-scans the affected packages.
- Alternatively decide the report was a false alarm and **Dismiss** it, or use the editor's other actions to ignore
  it or mark it as having no legal text.

## What happens after you accept something

Accepting a proposal or creating a pattern is not instantaneous across the whole system, and that is by design.
Cavil schedules a background re-scan of the packages the change affects (typically within a few minutes). On that
re-scan, the new pattern is applied, any duplicate snippets it now covers vanish, and the reports update. You do not
need to chase the duplicates yourself — that is the "resolved automatically" step doing its job.

## A worked example

1. A new package is scanned. A keyword pattern trips on the word "redistribute" inside a file header, capturing a
   snippet.
2. An AI assistant reviews it. The header is a complete, standard BSD-3-Clause notice, so the AI proposes a license
   pattern for it. The proposal appears on **Change Proposals**, marked "AI assisted".
3. A second snippet in the same package is an unusual, hand-written relicensing preamble. The AI cannot map it to a
   known license, so instead of guessing it **reports a missing license**. That appears on **Missing Licenses**.
4. You accept the BSD-3-Clause proposal — done in seconds.
5. You open the missing-license report, read the preamble, decide how it should be treated, author the pattern in the
   inline editor, and **Create Pattern**. The report leaves the queue.
6. Cavil re-scans the package. Both snippets are now resolved, and any other package containing the same BSD-3-Clause
   header or the same preamble wording will be understood automatically from now on.
