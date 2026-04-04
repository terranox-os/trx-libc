# trx-libc Git Workflow

*Defines branching, commit conventions, release strategy, and PR process for terranox-os/trx-libc.*

---

## Branching model: Trunk-based development

```
main ─────●──────●──────●──────●──────●──────●──── (always releasable)
           \    /  \    /        \    /
            feat    feat          feat
           (1-3d)  (1-3d)        (1-3d)

Tags:  v0.1.0-alpha.1    v0.1.0-beta.1    v0.1.0-rc.1    v0.1.0
       (Phase 0)          (Phase 1)        (Phase 2+3)    (stable)
```

### Rules

1. **`main` is always releasable.** Every commit on main must pass CI. No broken builds.
2. **Short-lived feature branches.** Branch from main, merge back within 1-3 days. Name: `<type>/<description>` (e.g., `feat/syscall-dispatch`, `fix/errno-mapping`, `test/malloc-stress`).
3. **No long-lived branches.** No `develop`, no `release/*`. Tags mark releases directly on main.
4. **PRs required.** All changes go through pull requests. Direct pushes to main are blocked.
5. **Squash merge.** Each PR becomes one commit on main. Clean linear history for git blame.

### Branch naming

```
feat/<description>    New functionality (syscall wrappers, stdio, malloc)
fix/<description>     Bug fixes
test/<description>    Test additions or improvements
docs/<description>    Documentation only
ci/<description>      CI/build system changes
refactor/<description> Code restructuring without behavior change
perf/<description>    Performance improvements
```

---

## Commit message convention: Angular/Karma

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type | When to use |
|------|------------|
| `feat` | New functionality (new syscall wrapper, new header, new POSIX function) |
| `fix` | Bug fix |
| `docs` | Documentation only (comments, README, CLAUDE.md) |
| `test` | Adding or fixing tests |
| `ci` | CI/build system changes (BUILD.bazel, build.zig, GitHub Actions) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `style` | Formatting, whitespace (no logic change) |
| `chore` | Maintenance (dependency updates, tooling) |

### Scopes (match directory structure)

| Scope | Directory | Examples |
|-------|-----------|---------|
| `syscall` | `src/arch/`, `src/internal/` | `feat(syscall): add syscall4 for 4-arg dispatch` |
| `crt` | `src/crt/`, `src/arch/*/crt0` | `feat(crt): implement __libc_start_main` |
| `string` | `src/string/` | `feat(string): add strchr and strrchr` |
| `stdio` | `src/stdio/` | `feat(stdio): implement FILE buffered write` |
| `stdlib` | `src/stdlib/` | `feat(stdlib): add qsort with introsort` |
| `malloc` | `src/malloc/` | `feat(malloc): implement small-bin allocator` |
| `pthread` | `src/pthread/` | `feat(pthread): add futex-based mutex` |
| `net` | `src/net/` | `feat(net): add socket/bind/listen wrappers` |
| `signal` | `src/signal/` | `feat(signal): add dispatch thread model` |
| `ctype` | `src/ctype/` | `feat(ctype): add comptime lookup table` |
| `errno` | `src/errno/` | `fix(errno): map DEVICE_OFFLINE to ENOENT` |
| `time` | `src/time/` | `feat(time): add clock_gettime wrapper` |
| `unistd` | `src/unistd/` | `feat(unistd): add read/write/close` |
| `fcntl` | `src/fcntl/` | `feat(fcntl): add open with O_* flags` |
| `terranox` | `src/terranox/` | `feat(terranox): add capability grant/revoke wrappers` |
| `headers` | `include/` | `feat(headers): add sys/mman.h with mmap constants` |
| `build` | `BUILD.bazel`, `build.zig` | `ci(build): add cross-compile for aarch64` |

### Subject rules

- Imperative mood: "add", "fix", "change" — not "added", "fixes", "changed"
- No period at the end
- Max 72 characters
- Lowercase first letter

### Body rules

- Wrap at 72 characters
- Explain **what** and **why**, not how (the diff shows how)
- Reference issues: `Closes #12`, `Fixes #34`

### Breaking changes

```
feat(syscall)!: change syscall dispatch to use SyscallNr enum

BREAKING CHANGE: __trx_syscall* functions now take SyscallNr enum
instead of raw u32. All callers must update.
```

The `!` after the scope and/or `BREAKING CHANGE:` footer triggers a major version bump.

### Examples

```
feat(syscall): add x86_64 SYSCALL dispatch for 0-6 args

Implements __trx_syscall0 through __trx_syscall6 using Zig inline
assembly. Register mapping follows terranoxos-syscall-ref.md Part II:
rax=number, rdi/rsi/rdx/r10/r8/r9 for args 1-6.

The r10 substitution for rcx (4th arg) is handled in syscall4-6
because the SYSCALL instruction clobbers rcx and r11.
```

```
fix(errno): handle kernel -ENODEV for offline display

gen_result_to_errno mapped DISPLAY_OFFLINE to EINVAL, but ENOENT
is more appropriate (device not found). Matches the convention
used for DEVICE_OFFLINE.

Fixes #42
```

```
test(malloc): add stress test for concurrent small allocations

Allocate and free 10,000 8-byte blocks in a loop to exercise the
small-bin free list. Verifies no double-free or corruption.
```

---

## Release strategy: Phase-based pre-releases (SemVer)

### Version scheme

```
v0.1.0-alpha.N   Phase 0: syscall layer + crt0 + hello world
v0.1.0-beta.N    Phase 1: core POSIX (string, stdlib, stdio, unistd)
v0.1.0-rc.N      Phase 2+3: malloc + pthreads
v0.1.0           First stable: enough to run real C programs

v0.2.0-alpha.N   Phase 4: networking
v0.2.0-beta.N    Phase 5: signals
v0.2.0-rc.N      Phase 6: TerranoxOS extensions
v0.2.0           Full POSIX + extensions

v0.3.0           Phase 7: AArch64 + RISC-V 64 arch ports
v1.0.0           Production-ready, POSIX conformance tested
```

### Release process

1. **Tag on main**: `git tag -a v0.1.0-alpha.1 -m "Phase 0: syscall dispatch + crt0 + hello world"`
2. **GitHub Release**: Auto-generated from tag via CI, includes CHANGELOG excerpt
3. **No release branches**: Trunk-based — fixes go to main and get a new tag (alpha.2, alpha.3, etc.)
4. **CHANGELOG.md**: Updated in the same PR that bumps the version. Uses Keep a Changelog format.

### When to tag

| Milestone | Tag |
|-----------|-----|
| `_start` reaches `main`, `write()` works, `_exit()` works | `v0.1.0-alpha.1` |
| string.h + stdlib.h + ctype.h complete | `v0.1.0-beta.1` |
| stdio.h (printf, FILE, fopen) complete | `v0.1.0-beta.2` |
| malloc works (thread-safe) | `v0.1.0-rc.1` |
| pthreads work (create, join, mutex, cond) | `v0.1.0-rc.2` |
| All Phase 0-3 tests pass, svmcheck clean | `v0.1.0` |

---

## PR process

### Creating a PR

1. Branch from main: `git checkout -b feat/stdio-printf`
2. Make commits (can be messy — they get squashed)
3. Push: `git push -u origin feat/stdio-printf`
4. Create PR with descriptive title following Angular format: `feat(stdio): implement printf family`
5. PR body should include:
   - What changed and why
   - Test plan (what tests were added/run)
   - Breaking changes (if any)

### PR template

```markdown
## Summary
<1-3 bullet points>

## Test plan
- [ ] `zig test` passes
- [ ] svmcheck --verify clean
- [ ] New tests added for <feature>

## Breaking changes
None / <description>
```

### Merge rules

- **Squash merge only.** PR title becomes the commit message on main.
- **PR title must follow Angular format.** `type(scope): description`
- **CI must pass.** All tests green, svmcheck clean, cross-compile succeeds.
- **At least one approval** (or self-merge for solo development with CI gate).

### After merge

- Delete the feature branch (GitHub auto-deletes).
- Close linked issues via `Fixes #N` in the squash commit body.

---

## Git blame and bisect

### Why squash merge matters for blame

Each commit on main represents one logical change (one PR). `git blame` shows who introduced each line and which PR it came from. No noise from WIP commits, fixups, or merge commits.

```bash
git blame src/stdio/printf.zig
# Every line maps to a single PR commit with a clear Angular message
```

### Bisect

Since main is always green (CI enforced), `git bisect` works cleanly:

```bash
git bisect start
git bisect bad HEAD
git bisect good v0.1.0-alpha.1
# Binary search through squash commits — each is self-contained and testable
```

---

## CI gates (enforced on every PR)

```yaml
checks:
  - zig build (freestanding, x86_64)
  - zig test (host, pure-function tests)
  - zig fmt --check (formatting)
  - svmcheck --verify (bytecode verification)
  - svmcheck --contracts (syscall contract validation)
  - cross-compile: aarch64-freestanding, riscv64-freestanding
```

All must pass before merge is allowed.

---

## Repository settings (GitHub)

```
Branch protection on main:
  ✓ Require PR before merging
  ✓ Require status checks to pass (all CI jobs)
  ✓ Require linear history (squash merge only)
  ✓ Do not allow bypassing settings
  ✓ Auto-delete head branches after merge

Merge button:
  ✓ Allow squash merging (default)
  ✗ Allow merge commits (disabled)
  ✗ Allow rebase merging (disabled)
  ✓ Default to PR title for squash commit message
```

---

## Submodule: kernel-libs

trx-libc depends on genesis-abi C headers via `@cImport`. kernel-libs is a git submodule:

```
trx-libc/
├── deps/
│   └── kernel-libs/    (git submodule → terranox-os/kernel-libs)
├── src/
│   └── internal/
│       └── syscall.zig  # @cImport("genesis_syscall.h") via deps/kernel-libs/genesis-abi/include/
└── BUILD.bazel
```

### Updating the submodule

```bash
cd deps/kernel-libs
git fetch origin && git checkout v0.2.0   # pin to a specific tag
cd ../..
git add deps/kernel-libs
git commit -m "chore(deps): update kernel-libs to v0.2.0"
```

Pin to tags, not branches. This ensures reproducible builds.
