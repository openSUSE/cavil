# Roles and Capabilities

Cavil authorizes actions by **capability**, not by role name. Roles are named bundles of capabilities;
every gate — a web route, an in-controller check, a frontend affordance, an MCP tool scope — asks "does
the user have capability X?" and resolves it through a single map in
[`Cavil::Role`](../lib/Cavil/Role.pm). No gate names a role directly, so each role's authority stays
explicit and a capability's reach can be changed in one place.

## Capabilities

| Capability | What it allows |
|---|---|
| `view` | Read reports, review results, licenses, snippets, statistics (much of this is public anyway). |
| `classify` | Validate AI text-classification results, creating training data. |
| `propose` | Propose changes — patterns, ignore lines, ignore globs, new snippets, missing-license reports. Proposals need a curator to take effect. |
| `curate` | Curate the corpus and drive reviews: create/edit/remove patterns, manage ignores, accept/reject change proposals, apply snippet batch decisions, reindex, and finalize reviews (accept/reject). |
| `infra` | Operate the instance: the Minion job dashboard and package upload. |
| `review` | Move a report from `new` to `acceptable` (a non-lawyer expert sign-off). |
| `review_lawyer` | Move a report from `new` to `acceptable_by_lawyer` — the legal sign-off. |

## Roles

`user` and `admin` are the two base roles; the others are extensions that add capabilities. `admin`
and `lawyer` share the same **curator core** (`view`, `classify`, `propose`, `curate`, `review`) and
then differ by exactly one capability each: `admin` additionally operates the machine (`infra`), while
`lawyer` additionally carries the legal sign-off (`review_lawyer`). So an admin is a curator who runs
the instance; a lawyer is a curator whose acceptance carries legal weight — and neither is a superset
of the other.

| Role | view | classify | propose | curate | review | infra | review_lawyer |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `user` | ✓ | | | | | | |
| `classifier` | ✓ | ✓ | | | | | |
| `contributor` | ✓ | | ✓ | | | | |
| `manager` | ✓ | | | | ✓ | | |
| `admin` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| `lawyer` | ✓ | ✓ | ✓ | ✓ | ✓ | | ✓ |

(The internal `bot` identity used by import/automation authenticates over the token API, not these web
role gates, and grants no web capabilities.)

## Capability → gate mapping

The routes and checks each capability protects (see [`Cavil.pm`](../lib/Cavil.pm) for the route gates):

- **`infra`** — the Minion dashboard (`/minion`) and package upload (`/upload`). Admin-exclusive; this
  is the *only* thing a lawyer cannot do that an admin can.
- **`curate`** — reindex; pattern create/edit/remove and license metadata; ignore-match and
  ignore-glob management; the `review_package` endpoint (accept/reject); accepting a change proposal
  (creating the real pattern) and rejecting one (`remove_proposal`, which a proposal's owner may also
  do); snippet batch decisions that apply directly; note moderation; visibility of lawyer-only notes.
- **`propose`** — creating snippets from a file and proposing batch decisions (contributors, plus
  curators who can also apply directly).
- **`classify`** — approving snippet classifications.
- **`review`** — the manager `fasttrack_package` accept path.
- **`review_lawyer`** — see the invariant below.

## The `acceptable_by_lawyer` invariant

`acceptable_by_lawyer` means *a lawyer signed off*, so it is **always derived from the
`review_lawyer` capability and never taken from the request**. On both the web (`review_package`) and
MCP (`cavil_accept_review`) paths, accepting a report sets `acceptable_by_lawyer` when the acting user
holds `review_lawyer` and plain `acceptable` otherwise. A non-lawyer curator (for example a plain
admin) can therefore accept a package but can never mint a lawyer sign-off, even by posting the field
directly. This is enforced server-side and pinned by the authorization matrix in
[`t/roles.t`](../t/roles.t).

## Assigning and changing roles

Roles are stored per user (`bot_users.roles`) and managed with the `cavil user` command. A user's
capabilities are the union of their roles', effective on the next request. A lawyer needs only the
`lawyer` role to curate and sign off; `admin` is for users who also operate the instance.
