# QA Findings Log

A living log of every bug and UX gap discovered during E2E test runs and
exploratory testing of rawenv. Each finding gets an ID, is triaged by severity,
and is tracked from discovery through resolution.

> **Process rule:** Every **blocker** and **major** finding MUST be converted
> into a user story (and linked here) **before VERIFY-040** runs. Minor and
> trivial findings may be batched or deferred, but must still be recorded.

---

## Summary

| Metric | Count |
|--------|-------|
| Total findings | 0 |
| 🔴 Open | 0 |
| 🟢 Resolved | 0 |
| ⛔ Blockers (open) | 0 |
| 🟠 Majors (open) | 0 |

**Status:** No findings logged yet. Log is initialized and ready for E2E /
exploratory runs.

---

## Severity Definitions

| Severity | Meaning | Action required |
|----------|---------|-----------------|
| ⛔ Blocker | Core flow broken, data loss, crash, or security hole. Cannot ship. | Convert to user story before VERIFY-040 |
| 🟠 Major | Important feature degraded or broken; notable UX failure with no easy workaround. | Convert to user story before VERIFY-040 |
| 🟡 Minor | Cosmetic or low-impact issue with an easy workaround. | Record; fix opportunistically |
| ⚪ Trivial | Nitpick, typo, polish. | Record; batch later |

## Status Definitions

| Status | Meaning |
|--------|---------|
| `open` | Reproduced and recorded, not yet fixed |
| `in-progress` | Fix underway (story exists / branch open) |
| `resolved` | Fix landed and verified |
| `wontfix` | Acknowledged, intentionally not fixed (include rationale) |
| `duplicate` | Same root cause as another finding (link it) |

---

## Findings

Each finding uses the template below. IDs are sequential: `QF-001`, `QF-002`, …

<!--
### QF-001 — <short title>

- **Date:** YYYY-MM-DD
- **Severity:** ⛔ Blocker | 🟠 Major | 🟡 Minor | ⚪ Trivial
- **Status:** open | in-progress | resolved | wontfix | duplicate
- **Area:** CLI / TUI / GUI / network / deploy / install / docs / …
- **Source:** E2E (`<test name>`) | exploratory | CI | user report
- **Environment:** OS + version, rawenv version/commit

**Steps to reproduce**
1. …
2. …

**Expected**
> What should happen.

**Actual**
> What actually happened (include error output / screenshot path).

**Fix**
> Root cause + the change that resolved it (or "pending"). Link the commit/PR.

**User story:** <link to story / issue, required for blocker & major before VERIFY-040>
-->

_No findings recorded yet._

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-10 | Log created and initialized (QA-050). |
