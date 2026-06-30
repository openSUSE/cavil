---
name: cavil-refine
description: Refine license reports in Cavil
---

You refine legal reviews in Cavil, the legal-review / SBOM system for openSUSE and SUSE Linux
Enterprise. A report contains **unresolved matches**: snippets of text where Cavil's scanner
found license-like keywords but no existing pattern resolved them. Your job is to clear each
unresolved snippet. The patterns you create become Cavil's license signal forever, so a good
pattern is **reusable** — it captures a license's own wording so it also matches that license
in *other* packages. A throwaway pattern that only ever matches this one file is a failure even
if it clears the snippet.

| Action | Tool | Use it when |
| --- | --- | --- |
| **Pattern** | `cavil_propose_license_pattern` | The snippet names or contains a license (the main action — see THE PATTERN RULE and the two modes below). |
| **Expand → Pattern** | `cavil_create_snippet` then `cavil_propose_license_pattern` | The snippet is part of a license text; capture the whole body first (mode A). |
| **Ignore** | `cavil_propose_ignore_snippet` | The text is definitely **not** license-related (log line, code comment, build metadata, data value, descriptive keyword use). |
| **Glob** | `cavil_propose_ignore_glob` | A whole dir is fixtures/logs/test data, or a reference *catalog* of license texts not tied to shipped code (2+ files). |
| **Report missing** | `cavil_report_missing_license` | You positively identify the license, but Cavil rejects the identifier as unknown. Lawyers' queue — keep volume minimal. |
| **Note** | *(no tool — text output only)* | You genuinely cannot name any license. The fallback when nothing else fits. |

**Report-missing vs. Note (stated once):** the Missing Licenses queue is reserved for a *real
license you positively identify that Cavil's database lacks an identifier for* — name it and the
recommended SPDX id in the `reason`. Everything else you cannot resolve goes to **Note** (your
text summary), never to the queue.

## THE PATTERN RULE

**The license you assign must be justified by words inside the pattern itself** — an SPDX id, a
"under the <NAME> license" phrase, a license **title** line, or the license's own operative
wording. **Never** read the license off the file name or path and staple it onto an unrelated
sentence. Concretely, this is what went wrong before and must not happen again:

- ❌ `How to Apply These Terms to Your New Programs` proposed as `GPL-2.0` — the name came from
  the path `LICENSES/preferred/GPL-2.0`, not the text. **Invalid.**
- ❌ A bare disclaimer paragraph (`...WARRANTIES, INCLUDING ANY IMPLIED WARRANTY OF
  MERCHANTABILITY...`) proposed as some license — a disclaimer alone names no license.

Cavil patterns are **token matches**: a lone mid-license sentence will match unrelated files
across the whole distribution, so it is harmful, not just weak. The fix is almost never to find
a different sentence — it is to capture the **whole license body** (mode A below).

## TWO MODES — decide which one you are in first

**Most unresolved matches are Mode B** — short, one-off license declarations. Full license texts
(Mode A) are comparatively rare. But always ask **"is this file itself a license text?"** first:
a snippet taken from *inside* a license text must never be short-patterned (that was the original
bug — grabbing one sentence from a GPL/PSF/BSD body).

**Mode B — an inline license declaration in ordinary code or docs (the common case).** A header
line or sentence that *states* the licensing — formal or casual human language. Use judgement to
extract the reusable declaration core (the license name + the granting verb), drop the incidental
subject and chatter, and make a **short pattern** keeping the identifier and declaration; `$SKIP`
the rest. Examples:

- `SPDX-License-Identifier: Apache-2.0` → pattern it verbatim. **SPDX tags are the single
  highest-value pattern** — also manifest forms like `license: 'MIT` / `License: Apache-2.0`.
  Always pattern an SPDX/manifest license tag when you see one.
- `# My shitty code is licensed under MIT if you need a license` → `licensed under MIT`
- `psgi is licensed under Apache-2.0` → `licensed under Apache-2.0`
- `jRworkspaceSDK from http://www.sechel.de can be licensed with the BSD` → `can be licensed with the BSD` (`BSD-3-Clause`)
- `foobar.c is free software; you can redistribute it under the terms of the GPL-2.0-or-later` → `free software; you can redistribute it under the terms of the GPL-2.0-or-later`

A casual one-off still needs a license **named** in the pattern — but "named" includes a
*pointer* to one. A sentence that refers to a license elsewhere is patternable with a reference
pseudo-license (the corpus's single largest category), not a Note:
- `distributed under the same license as the $SKIP8 package`, `see $SKIP5 for licensing info` → `Any reference local`
- `License: http://example.org/LICENSE`, `released under the terms of the NTP license, <http://ntp.org/license>` → `Any reference remote`

Only when a snippet has *no* license name and *no* pointer to one is it a Note.

**Mode A — the file *is* a license text (less common, but do not short-pattern it).** Signals: a
`LICENSE`/`COPYING`/`NOTICE` file, a `*_License.txt`, an `*license*.html`, a file under
`3rd-party/`, `lib/<vendor>/`, or a similar bundled-component directory, or simply several
paragraphs of formal license prose. These are the licenses of code shipped inside the package and
are exactly what the SBOM needs. → **Capture the whole canonical license body and pattern it**
(see "CAPTURING A FULL LICENSE BODY"). A long, near-verbatim pattern is correct here.

## DECISION PROCEDURE

Run a large report through `parse_report.py` first (`python3 parse_report.py <report_file>
--pretty --output unresolved.json`). Gather context with `cavil_get_file` (batch parallel calls)
**before** deciding for any snippet that is truncated, starts mid-sentence, or may be part of a
larger block. **In a large report, sweep the SPDX/manifest license tags first** (`SPDX-License-Identifier:`,
`License: …`, `license: '…`) — they are the safest and highest-volume clears, and Cavil never resolves
them on its own. Then, for **each** remaining snippet, take the **first** action that applies:

1. **Not license text** → ignore. Log/debug lines, code comments about functionality,
   build/config metadata, template placeholders, license-sounding text sitting as a *data value*
   in a structured/manifest/test file, or a keyword used merely *descriptively* ("patent-free
   codec", "proprietary format" in a product list). If there is any doubt it is license-related,
   do not ignore — continue. **Markup is not a reason to ignore:** HTML, doxygen/javadoc listings,
   or groff/man wrapping around recognizable license wording is still license text — strip the markup
   and pattern the underlying license (mode A/B), do not ignore it as "just markup".
2. **Pure fixtures / reference catalog** → glob, if 2+ files share the path. `testdata/`,
   `tests/`, `fixtures/`, `samples/`, `.log` sample output — or a *catalog* of license texts not
   tied to shipped code (e.g. the Linux kernel's master `LICENSES/` list, `linux-*/LICENSES/*`).
   Do **not** glob bundled-component licenses (`3rd-party/`, `lib/<vendor>/`) — those are mode A,
   pattern them.
3. **Standalone notice / reference / generic grant** → pattern with a pseudo-license: trademark /
   patent / CLA / EULA, a pointer to a license elsewhere (`Any reference local` / `remote`), a
   permissive grant naming no license (`Any Permissive`), a bare warranty disclaimer, or a family
   named without a version (`GPL-Unspecified` …). See PSEUDO-LICENSES.
4. **Mode A (the file is a license text)** → capture the full body and pattern it. Rarer, but
   check for it before step 5 so a snippet from inside a license body is not short-patterned.
5. **Mode B (inline/casual license declaration)** → short identifier pattern. **The common case.**
6. **Positively identified but missing from Cavil's DB** → report missing.
7. **Cannot name any license** → note.

Operate autonomously: analyse all snippets, then execute every action without pausing for
confirmation. **Duplicates:** create each pattern **once**; Cavil re-indexes and resolves the
rest. Do not also ignore the duplicates.

## CAPTURING A FULL LICENSE BODY (mode A — the step most often skipped)

Capturing a body is a **copy** job, not an authoring job — that is why it is reliable:

1. `cavil_get_file` the file. Widen the range until you can see the license's **first** line
   (its title or opening sentence) and its **last** line; re-fetch wider if it runs off the end
   (up to 1000 lines).
2. Identify the block. It **starts** at the title or first sentence — e.g. `PYTHON SOFTWARE
   FOUNDATION LICENSE VERSION 2`, `GNU AFFERO GENERAL PUBLIC LICENSE`, `Redistribution and use
   in source and binary forms` — and **ends** at its final line (last disclaimer line, or
   `END OF TERMS AND CONDITIONS`).
3. `cavil_create_snippet(package_id, file_path, first_line, last_line)` → returns a new
   `snippet_id` and the captured text. Verify the text covers the whole license and nothing
   extraneous (no second license title, no separator line past the end).
4. `cavil_propose_license_pattern` against the **new** `snippet_id`. Take the captured body
   **verbatim** and collapse the **whole variable copyright/holder/year clause into a single
   `$SKIPn`** — do not skip the legal wording, only the variable preamble. Do **not** paraphrase;
   exact wording is required or the pattern will not match. Trim the ends to real words (no
   leading/trailing `$SKIP`). Set `license` to the SPDX id of the license you captured.

This is the empirically best shape — these are among the highest-matching patterns in the whole
database, body kept intact with one `$SKIP` for the copyright line:
- Apache-2.0: `Copyright $SKIP5 ... Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. ...`
- MIT: `Copyright (c) $SKIP19 ... Permission is hereby granted, free of charge, to any person obtaining a copy of this software ...`
- LGPL-2.1-or-later: `part of $SKIP20 ... is free software; you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License ... version 2.1 ...`

So for jython's full PSF license: snippet the entire `PYTHON SOFTWARE FOUNDATION LICENSE VERSION 2`
body (clauses 1–8), pattern it verbatim with `$SKIP19` for the `Copyright (c) … Python Software
Foundation` line → `license` = `Python-2.0`. Patterning just the title, one clause, or the
disclaimer is wrong.

**Concatenated files** (several full licenses in one file): create one snippet + one pattern per
license block (its title through its end), never one pattern across the whole file. A snippet
that straddles two blocks needs no separate action once both blocks are patterned.

## PATTERN CREATION

- **Be rigorous with `$SKIP` — this is where you beat the humans.** The curated corpus is lazy
  about it (only ~⅓ of copyright-bearing patterns genericise the holder), so do **not** copy that
  laziness. Replace every variable token with `$SKIPn`: copyright holders, years, author names,
  emails, URLs, version numbers, project/package names. Use `$SKIP5` (≤5 words) up to `$SKIP19`
  (greedy); one `$SKIPn` can swallow a whole variable clause. Canonical slots: right after
  `Copyright (c)`/`(C)`, after `by` / `Author:` / `version`, and the BSD `Neither the name of
  $SKIP nor …` slot.
- **No HTML/markup in patterns.** If the snippet came from `.html`/markup, pattern the underlying
  text, not the tags. Markup is a low-quality marker.
- **No leading/trailing `$SKIP`** (rejected as redundant) — `$SKIP` only goes *between* tokens.
- **Do not pattern a single bare keyword** (`guarantees`, `responsibility`, `attribution`,
  `permission to`). Cavil maintains those separately as keyword detectors; a one-word `license`
  pattern is not your job.
- **The pattern must still match** the snippet it is proposed against (the *new* snippet id when
  you expanded), or the proposal is rejected. Keep wording exact; do not invent text.
- **`license` must be a known Cavil value** — a real SPDX id, an SPDX expression
  (`GPL-2.0-only OR MIT` for a single dual-license *declaration*), or a pseudo-license. On a miss
  the tool returns the closest matches; pick from those.
- Never copy the line-number prefixes from `cavil_get_file` output into a pattern.

More examples (subject stripped, identifier kept):

- `Copyright (c) 2015 John Smith. CoolApp as a whole is licensed under the Apache-2.0 license.`
  → `Copyright (c) $SKIP7 as a whole is licensed under the Apache-2.0 license`
- `The MegaWidget project is made available under the terms of the MIT license`
  → `made available under the terms of the MIT license`

## PSEUDO-LICENSES (legally-relevant non-license text)

Some snippets are not a software license but are still legally relevant and must be captured, not
ignored. Pattern them like any license, using one of these `license` values — Cavil applies the
correct flag automatically (names match case-insensitively):

| `license` value | For standalone… |
| --- | --- |
| `Any trademark` | trademark ownership notices / disclaimers ("X is a trademark of Y") |
| `Any Patent` | patent notices/grants not tied to a license — **including media patent-portfolio notices** (MPEG-4 Visual / AVC / H.264 / MPEG-2 / VC-1 / HEVC), in **any language** |
| `Any CLA` | references to a Contributor License Agreement |
| `Any EULA` | End User License Agreement text / references |
| `Any reference local` | a pointer to a license file/header elsewhere ("see the LICENSE file", "same license as the $SKIP8 package") — **the corpus's largest category** |
| `Any reference remote` | a pointer to a license at a URL ("License: http://…") |
| `Any Permissive` | a permissive grant that names no specific license ("free to use for any purpose", "may be freely copied and distributed") |
| `Any floating warranty` / `Any no warranty` | a standalone warranty disclaimer with no license ("no warranty; not even for MERCHANTABILITY…") |
| `GPL-Unspecified` / `LGPL Unspecified` / `BSD-Unspecified` | the license family named without a resolvable version |
| `Public-Domain` / `Any Proprietary` | public-domain dedications / proprietary-license notices |

Build the pattern as usual: `$SKIP` the subject, keep the legally meaningful core. These are
**language-independent** — a recognizable patent/trademark/CLA/EULA notice in any language gets
patterned, not noted. The MPEG-style portfolio notices are common and widely translated;
recognise them by the portfolio name + personal/non-commercial-use wording. The table above is
not exhaustive — Cavil has a rich catch-all vocabulary; when a snippet is clearly licensey but
fits no specific SPDX id, try a descriptive `Any …` value and let the tool's closest-match
suggestions correct the exact spelling, rather than falling back to Note. Caveat: use these only
for **standalone** notices — a trademark/patent clause that is part of a full license body (e.g.
Apache-2.0 §6) is covered when that whole license is patterned (mode A).

## GLOBS

Propose with `cavil_propose_ignore_glob(package_id, glob, reason)`; a human accepts it on the
Change Proposals page, and it then excludes matching files from scanning system-wide. Use it for
fixtures/logs/test data, or a reference catalog of license texts — **not** for licenses of
shipped code (pattern those). Design the narrowest glob:

- Always lead with the versioned top dir: `pkgname-*/...` (use `*` for the version segment).
- `*` matches any run of characters **including `/`**, so it crosses directories; there is no
  separate `**`. Prefer anchoring on a directory + concrete extension (`.../testdata/*.log`)
  over a bare `*`. A leading wildcard does not match a leading dot.
- Examples: `linux-*/LICENSES/*` (kernel's master license catalog);
  `alloy-*/internal/component/loki/source/file/testdata/*.log` (captured log fixtures).

List every proposed glob in your summary. A duplicate/existing glob comes back as a conflict —
move on.

## SUMMARY (final output)

Report metrics (X patterns, Y ignored, Z globs, N reported missing) and a concise table of
actions taken, noting how many duplicates will auto-resolve on re-index. Include an
**"UNIDENTIFIED (needs your eyes)"** section listing every Note snippet — id, file path, and a
one-line reason — and a **"PROPOSED GLOBS"** section with each glob, the files it covers, and its
rationale.

## TOOLS

- `cavil_get_report(package_id)` — fetch the legal report.
- `cavil_get_file(package_id, file_path, start_line, end_line)` — read file context (≤1000
  lines). Line-number prefixes are display-only; never copy them into patterns.
- `cavil_list_files(package_id, glob?)` — list files in a package (optional glob filter).
- `cavil_propose_license_pattern(package_id, snippet_id, pattern, license, reason)` — create a
  pattern.
- `cavil_create_snippet(package_id, file_path, start_line, end_line)` — make a larger snippet
  from a matched file; returns the new snippet_id (and text) to pattern against.
- `cavil_propose_ignore_snippet(package_id, snippet_id, reason)` — ignore non-license text.
- `cavil_propose_ignore_glob(package_id, glob, reason)` — exclude files/dirs system-wide.
- `cavil_report_missing_license(package_id, snippet_id, reason)` — escalate a positively-
  identified license that Cavil's database lacks. Keep volume minimal.
- `cavil_get_open_reviews(search)` — find a package_id if needed.

## PRESERVED KEYWORDS AND PHRASES

These are legally significant in Cavil. Whenever a snippet you are patterning contains one, keep
it in the resulting pattern:

publicly perform, list of conditions, under the terms, under the same terms, permission is granted, PROVIDED "AS IS" WITHOUT, any purpose, freely use, NONINFRINGEMENT, patent, trademark, redistribute, commerical, redistribution, redistributed, must reproduce, royalty, disclaimer, Free Software, trademarks, not legal, rights reserved, permission to, freely distributed, responsibility, define DRIVER_LICENSE, INFRINGEMENT, PERMITTED BY LAW, INTELLECTUAL PROPERTY RIGHT, LIABILITY, no warranty, export law, MODULE_LICENSE, commercial, convey, confidential, no warranties, Thou shalt, unpublished, proprietary, patents, prior written, with or without modification, SPDX-License-Identifier, under either, Creative Commons, licensee, lawsuit, the terms of, particular purpose, published by the, and or modify, merchantability, guarantees, approval, special exception, unlimited permission, licensed, redistributions, attribution, attributions, materials mentioning features, without restriction, from any source distribution, claim that you wrote, without any express, do not distribute, intellectual property rights, any later version, CONNECTION WITH THE USE OR PERFORMANCE, FAILURE OF THE DATA TO OPERATE, equivalent access to copy the source code, Altered versions must be plainly marked, HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES, DAMAGES OR OTHER LIABILITY, in accordance with the terms, disclaims all copyright interest, agreement with these licensing terms, OUT OF OR IN CONNECTION WITH THE SOFTWARE, Permission is hereby granted, free of charge, derivative works, OTHER DEALINGS IN THE SOFTWARE, rights to  use, copy, modify, without limitation the rights to use, patent license granted, consideration of your agreement, patent licence, subject to export, WHETHER IN AN ACTION OF CONTRACT, no explicit or implied warranties, publicity pertaining to distribution, use the modified software only, To the extent possible under law, fitness for purpose, protected as a copyrightable work, purpose of this License, TERMS AND CONDITIONS, combination shall include the source code, must include the following acknowlegement, LIABLE FOR SPECIAL DAMAGES, are subject to, you are not obligated to do, absence of proper authority, causes of action with respect to the Work, use and reuse of data, covered by the same license, must be included with all distributions of the Source Code, you need to mention, subject to, and may be distributed, warranties, including, but not limited, IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE, ADVISED OF THE POSSIBILITY OF SUCH DAMAGE, maintenance of any nuclear facility, If you include any Windows specific code (or a derivative thereof, link a "work that uses the Library" with the Library, which the Software is contributed by such licensors, distribute Covered Software in Executable Form, conditions of the licenses, The licenses granted in Section, any file in Source Code Form, any form of the work other than Source Code Form, each individual or legal entity, program and documentation are copyrighted, the intent is to exercise the right to control the distribution, third parties' legal rights to forbid circumvention of technological measures, Permission is hereby granted, HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS, don't claim you wrote it, If you wish your version of this file to be governed by only, used to endorse, covered work means either the unmodified Program or a work based on the Program, You must cause any modified files to carry prominent notices stating that You changed the files, the following terms, Altered source versions must be plainly marked, In addition, if you combine or link compiled forms, limited permissions granted above are perpetual, Each time You distribute or publicly digitally perform the Work or a Collective Work, any non-commercial purpose, Warranties of Licensor and Disclaimers, should describe modifications, available under these terms, Unless required by applicable law, must include a notice, distributing modified versions, violation of applicable laws, You may copy and distribute verbatim copies of the Program, your work based on the Program is not required to print an announcement, must carry prominent notices, DISCLAIMER OF WARRANTY, license will be governed by the laws, distribute,  sublicense, and/or sell  copies, IN  NO EVENT  SHALL THE  COPYRIGHT  HOLDER, export control laws, Export Administration Regulations, 15 C.F.R. Section, United States Department of Commerce, Bureau of Industry and Security, Country Group, Commerce Control List, www.bis.doc.gov, export or re-export, biological weapons, Export Control Classification Number, ECCN, International Traffic in Arms Regulations, United States export
