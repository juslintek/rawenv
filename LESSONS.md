# rawenv — Lessons Learned and Validation Rules

## Critical Lessons

### 1. Subagent Output Verification
NEVER trust subagent claims of "all tests pass" without running zig build test yourself AFTER all agents complete. Subagents verify their own module in isolation but miss cross-module conflicts.

### 2. Zig Version Pinning
Local Zig (0.15.2) differed from CI (0.14.0). ArrayList API changed between versions. ALWAYS check zig version and pin CI to match.

### 3. Stubs vs Working Code
Subagents create architecturally correct stubs with passing unit tests but NOT working end-to-end features. A config parser unit test is NOT a working rawenv init command. ALWAYS verify by running the actual user-facing command.

### 4. Cross-Platform
POSIX APIs (tcgetattr) don't exist on Windows. ALWAYS use comptime builtin.os.tag guards. Test cross-compilation locally before pushing.

### 5. Secrets
Never hardcode API keys. GitHub Push Protection blocks pushes with secrets.

### 6. Git History
.kiro/ and agent configs must NEVER be committed. Add to .gitignore BEFORE first commit.

## Validation Protocol
After EVERY subagent run or before ANY push:
1. zig build test — full test suite
2. zig build — release build
3. Run actual CLI commands (rawenv --help, rawenv tui, etc.)
4. Cross-compile: zig build -Dtarget=x86_64-linux, x86_64-windows
5. grep for secrets in staged files
6. Verify .kiro not in git

## Project State (2026-04-15)
- Repo: github.com/juslintek/rawenv — CI green, v0.1.0 released
- Status: SCAFFOLDED but NOT FUNCTIONAL — stubs need real implementation
- All user-facing features from prototype are unimplemented
