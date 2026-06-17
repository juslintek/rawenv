# QA Feedback — UX observations

Iteration 1 of 5 · 2026-06-17.

1. **CLI vs GUI detection divergence (confusing) [P1].** `rawenv detect` / `init` / `status`
   run in a monorepo root (e.g. `gratis/`) report the WRONG stack (php 8.4 + mysql) because only
   the GUI (`ProjectSetupVM.resolveStackRoot`) walks into the nested `gratis-suite/`. A CLI user
   gets a different — and wrong — answer than a GUI user for the same project. The CLI should
   resolve the nested stack root too, or print "stack found in ./gratis-suite — run there or use
   `--recursive`."

2. **WordPress→MySQL heuristic over-eager [P2].** A WordPress composer fingerprint emits `mysql`
   even when the real database is SQLite (gratis). Without the nested compose/Dockerfile the
   inference guesses MySQL; once the FrankenPHP/SQLite stack is resolved it should not also assert
   MySQL.

3. **Apple Music TCC prompt on dev machines [P3].** Shipping code is clean, but a stale TCC record
   for `io.rawenv.app` made the prompt appear on this machine. "Why does my dev tool want Apple
   Music?" is an alarming first impression. Recommend: document `tccutil reset MediaLibrary
   io.rawenv.app` for devs; add a build/packaging assertion that the Info.plist has no media
   usage keys / entitlement; consider a distinct dev bundle id so experimental builds don't
   pollute the release id's TCC store.

4. **Empty-detection projects give no feedback [P3].** `detect` on an unsupported project
   (FoxPro, Swift, plain HTML) returns `{"runtimes":[],"services":[]}` silently. A one-line
   "no supported manifest found (looked for package.json, composer.json, Cargo.toml, …)" would
   orient the user and reduce "did it even run?" confusion.

5. **Swift/SPM unsupported [P3].** `agent-router-swift` (`Package.swift`) detects nothing. If Swift
   projects are in scope, add SPM detection; if not, state the non-goal in `rawenv detect` output
   and the docs.

6. **Positive UX confirmed.** Single-instance launch (no Dock flood), calm dashboard chrome,
   8-item sidebar, clear stat cards and detail tabs; the FrankenPHP/php-8.5 nested detection now
   "just works" through the GUI setup flow.
