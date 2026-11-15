# tasks/P2-008-gomod-diff.md

phase: 2
goal: `lake --dir eval/diff exe mitos-diff eval/diff` compares `GoMod.extractor` with the vendored `go mod edit -json` output of 13 pinned module versions, as ordered lists, lists each module's lines outside the model's subset, and exits 0 because its only 2 mismatches are triaged into a model issue. It needs no Go and no network.
statement: none in `statements.lock` (tooling task). The runner's own: `Diff.compare_eq_nil`, `Diff.verdict_clean`, `Diff.Keys.ofPlugin_eq_model` (cites `GoMod.run_eq`), `Diff.readings_offsets`, `Diff.Finding.ofFields_fields`, and the kernel fixtures `Diff.ofPlugin_wholeFile` and `Diff.unreadLines_wholeFile`
touches: eval/diff/ (new), this file, ops/runs/
must_not_touch: eval/score/, eval/fixtures/, eval/mutants/, examples/, core/, statements.lock, models.lock, gate/, eval/cheats/, .github/, .claude/, docs/, plan/, tasks/P2-011-toolchain-readiness.md, the root lean-toolchain and lakefile.toml, .coderabbit.yaml
checks: start check (S1), eval/diff build, toolchain match, axioms, pin check (offline and `--online`), selftest, refresh with Go 1.24.7 then a clean tree, the run with no Go on PATH, changed paths, run-log check, `plan-tasks.test.sh`, `gate` green in CI
budget: 12 iterations · 3h wall · 1M tokens
escalation: hint → automation → stronger model → pair → split → revisit statement

## Context
- Plan row P2-008 in `plan/phase-2.md` (go.mod track, wave W3), issue #209. It waits for P2-007,
  which merged as #286 on P2-006 (#272). P2-012 (#213) waits for this row. Class A: an agent
  carries and merges it. `keptPath` (`gate/MitosGate/Land.lean`) names none of its paths.
- Owns: `eval/diff/` (new), "a Lake project with its own `lean-toolchain`, the pinned go.mod files
  and their vendored outputs". Reads: `examples/acme/Plugins/GoMod.lean`. Also must not touch:
  `eval/score/`, `eval/fixtures/`.
- Findings deferred here: the strict and lax parsers
  ([#209](https://github.com/kitimark/mitos/issues/209#issuecomment-6890502906), #275 item 3);
  P2-006's deferrals (a file Go rejects is reported as rejected, not as a mismatch; a quoted path
  is listed as outside the subset); P2-007's deferral (cite `GoMod.run_eq` wherever order
  matters); #282 and #292 item 1 (the gate does not pin order or count, `GoMod.run_eq` does);
  #160 item 2 (name the pinned repos, pin the Go version, check each licence).
- `tasks/P2-011-toolchain-readiness.md` expects `eval/diff/lean-toolchain` once this merges. This
  design keeps it: the file holds the root's `leanprover/lean4:v4.35.0`.
- No Go toolchain runs in CI. The comparison reads vendored files and starts no `go` process. Only
  `--refresh` runs Go, and the nightly refresh is P2-012's.
- Role: PR owner, routine (sonnet, high). The Lean text below is final and builds as written, so
  the work is vendoring, running and reporting. A proof that stops closing after the toolchain
  moved goes to a PR owner on opus at xhigh (S6). The verifier is the model that did not write most
  of the diff.
- Written at plan time by an arena of two runners (opus and sonnet; the owner ruled `fable` out for
  its token cost) and a sonnet judge (Rationale, Synthesis decision). The runners built on `main` at
  `68e37a9`. The judge rebuilt the synthesis on `main` at `85981fe`; `examples/acme`, `core/Mitos`,
  `lean-toolchain` and `eval/score` are the same at both. The sketch type-checks and runs on Lean
  v4.35.0 with Go 1.24.7 (Rationale, Evidence).
- The design PR landed this file and removed `P2-008` from
  `.claude/scripts/plan-tasks.pending`. The builder leaves that owner path unchanged.

## Design
Written once at plan time and amended in place. `touches` and `must_not_touch` above are its file
lists.

depth: build. The files under `types` are the whole runner and its two scripts, final text, with
every proof written: no `sorry`. The vendored data is named with the commands that fetch it, and
each fetched `module.mod` is pinned by its go.sum hash. Built from a copy of `main` at `85981fe` on
Lean v4.35.0: `lake --dir eval/diff build` succeeded (46 jobs, no warning under `warningAsError`),
and the run printed the report under Usage. The named fixtures are F0 to F5 and T1 to T28.

revisit_when: none. P2-006 and P2-007 have merged, and the names under `types` are theirs on
`main`. Two later events touch this row, and neither is a redesign:
- P2-001b (#204) adds `FactKind.binds`. The runner never matches on `FactKind` (it filters with
  `==`), so it builds unchanged (#285 item 6 is the trap it avoids). The builder still runs S1.
- A plugin or model PR that renames `GoMod.run_eq`, `Models.GoMod.readings`, `readingsFrom`,
  `Mode.step` or `wholeFile` breaks this build. Nothing in CI builds `eval/diff` until P2-012 (R1).

modules: one topic per file. Line counts are those of the checked build. A build that outgrows this
map reports it as a deviation and does not split silently.
- `eval/diff/lakefile.toml`: the Lake project, 17 lines. Copies
  `eval/score/lakefile.toml`, with `[leanOptions] warningAsError = true` from
  `eval/mutants/lakefile.toml` and the lib `globs` of `examples/acme/lakefile.toml`.
- `eval/diff/lean-toolchain`: the root file's bytes, `leanprover/lean4:v4.35.0`.
- `eval/diff/lake-manifest.json`: written by Lake on the first build, in the shape of
  `eval/score/lake-manifest.json` (`acme`, then the inherited `mitos-core`; the same text with
  `mitos-score` changed to `mitos-diff`). Commit it.
- `eval/diff/.go-version`: `1.24.7`, the one place that names the Go release of the vendored
  outputs. `--refresh` reads it, and it is the format `actions/setup-go` reads with
  `go-version-file` (A3).
- `eval/diff/pins.tsv`: one header line and 13 pins (under `types`). The one list of cases.
- `eval/diff/licences.tsv`: reviewed source URLs and SHA256 for LICENSE and each required NOTICE,
  keyed to the pin's case, module, version and SPDX claim; no additional cases.
- `eval/diff/triage.tsv`: one header line and the 2 rsc-quote lines (under `types`).
- `eval/diff/cases/.gitattributes`: `* -text`, the line of `eval/fixtures/toy/.gitattributes`
  (plan, Shared files 5), so git never rewrites a vendored byte.
- `eval/diff/cases/<case>/module.mod`: the pinned go.mod, as `proxy.golang.org` serves
  `<module>/@v/<version>.mod`. `module.json`: what `go mod edit -json` of Go 1.24.7 prints for it,
  written by `--refresh` only. `LICENSE`, and `NOTICE` for grpc and prometheus: the repository's
  files at the version's tag. 110,605 bytes of go.mod, 206,746 of JSON, 80,851 of licence text.
- `eval/diff/Diff/Compare.lean`: what one go.mod says as two ordered key lists, and the comparison
  of two such, 80 lines. Pure, no imports. Copies the order of
  `examples/acme/Plugins/GoMod.lean`: one namespace, the definitions, then the statements.
- `eval/diff/Diff/Pins.lean`: the `pins.tsv` format, 24 lines. Copies
  `parseLabels` in `eval/score/Score.lean`.
- `eval/diff/Diff/Go.lean`: everything about Go, 50 lines: its JSON as `Keys`
  (the only module that imports `Lean.Data.Json`, so the wire format stops here), and the
  process, which is the one `go` environment, the version refusal and the `--refresh` writes.
- `eval/diff/Diff/Plugin.lean`: the plugin's side, 63 lines: `Keys` of
  `GoMod.extractor.run`, the lines the model reads as unread, the citation of `GoMod.run_eq`, two
  kernel fixtures and the lax-opener guard.
- `eval/diff/Diff/Triage.lean`: the `triage.tsv` format, a finding as fields and back,
  58 lines. Copies `parseLabels` in `eval/score/Score.lean`.
- `eval/diff/Diff/Report.lean`: one run's result, the verdict against triage and the Markdown,
  80 lines. Copies `Scorecard.render` in `eval/score/Score.lean`.
- `eval/diff/Main.lean`: the shell, 64 lines: the `eval/diff` layout, the case
  list and the exit codes. Copies `eval/score/Main.lean`: a usage string, one directory argument,
  IO only.
- `eval/diff/check-pins.sh` (80 lines, executable): the pins against their
  bytes and reviewed licence/NOTICE sources, with no Go; `--online` adds sum.golang.org and
  refetches each source URL against its reviewed hash.
- `eval/diff/selftest.sh` (162 lines, executable): the exit codes and the
  scripts, with no Go and no network.

### Usage (caller's view)

From the repository root. The comparison needs no Go:

```
lake --dir eval/diff exe mitos-diff eval/diff
```

It prints Markdown and exits 0 (measured, F0). The first lines:

```md
## go.mod differential run

`GoMod.extractor` against `go mod edit -json` of go1.24.7, which reads each file with the strict parser `modfile.Parse`. 13 pinned modules.

| Case | Module | Plugin facts | Go facts | Mismatches | Triaged | Lines outside the subset |
|---|---|---|---|---|---|---|
| argo-cd | `github.com/argoproj/argo-cd/v3@v3.6.1` | 310 | 310 | 0 | 0 | 39 |
| cobra | `github.com/spf13/cobra@v1.10.2` | 5 | 5 | 0 | 0 | 1 |
| etcd | `go.etcd.io/etcd/v3@v3.7.3` | 85 | 85 | 0 | 0 | 11 |
| gh-cli | `github.com/cli/cli/v2@v2.104.0` | 169 | 169 | 0 | 0 | 2 |
| go-redis | `github.com/redis/go-redis/v9@v9.23.0` | 8 | 8 | 0 | 0 | 6 |
| gopls | `golang.org/x/tools/gopls@v0.24.0` | 30 | 30 | 0 | 0 | 1 |
| grpc | `google.golang.org/grpc@v1.85.0` | 35 | 35 | 0 | 0 | 2 |
| kubernetes | `k8s.io/kubernetes@v1.37.2` | 210 | 210 | 0 | 0 | 35 |
| prometheus | `github.com/prometheus/prometheus@v0.316.0` | 252 | 252 | 0 | 0 | 1 |
| rsc-quote | `rsc.io/quote@v1.5.2` | 0 | 2 | 2 | 2 | 2 |
| tailscale | `tailscale.com@v1.104.7` | 548 | 548 | 0 | 0 | 3 |
| traefik | `github.com/traefik/traefik/v3@v3.7.19` | 404 | 404 | 0 | 0 | 5 |
| zap | `go.uber.org/zap@v1.28.0` | 9 | 9 | 0 | 0 | 1 |

Untriaged mismatches: none.
Stale triage lines: none.
```

Then one section per module, with each mismatch and its issue, and each line outside the subset
with its 1-based line number:

```
### rsc-quote

- module `rsc.io/quote`: only in Go (#<n>)
- require `rsc.io/sampler`: only in Go (#<n>)

Lines outside the subset:

- 1: `module "rsc.io/quote"`
- 3: `require "rsc.io/sampler" v1.3.0`
```

Exit codes: 0 when every mismatch has a triage line and every triage line matches a mismatch
(`Diff.verdict_clean`); 1 when not; 2 on bad input (a malformed TSV, a case directory that
`pins.tsv` does not list or the reverse, a missing or malformed `module.json`, a Go refusal under
`--refresh`). `selftest.sh` runs each code (T1 to T11).

Call sites:
- The nightly job (P2-012's design, not this row's). Go comes from `.go-version`, the pins are
  checked, the refresh rewrites the vendored outputs, and a byte that moved fails the job:

```
- uses: actions/setup-go@<pinned sha>
  with:
    go-version-file: eval/diff/.go-version
- run: eval/diff/check-pins.sh
- run: lake --dir eval/diff exe mitos-diff eval/diff --refresh > "$RUNNER_TEMP/diff.md"
- run: git diff --exit-code eval/diff/cases
```

- A builder or verifier: the plain run, then `--refresh` with Go 1.24.7 on `PATH`, then
  `git status --porcelain eval/diff`, which prints nothing.
- Triage. An untriaged mismatch is printed as the `triage.tsv` line to add, ending in `#?`. Find or
  file the model issue, paste the line with its number. A triage line that no longer matches is
  printed under "Stale triage lines" and fails the run too, so the file only holds live findings.
- Adding a pin (C is the case name, M the module path in lower case, V the version): the three
  fetches below, a row in `pins.tsv` whose hash column is the third field of the
  sum.golang.org line, a reviewed `licences.tsv` row binding M/V and SPDX to the source URL and
  SHA256 of LICENSE plus each required NOTICE, then `--refresh` and `check-pins.sh --online`.
  Review the source grant and notice conditions first; an unclear licence stops at S3.

```
mkdir eval/diff/cases/C
curl -sSf -o eval/diff/cases/C/module.mod https://proxy.golang.org/M/@v/V.mod
curl -sSf https://sum.golang.org/lookup/M@V | grep -F 'M V/go.mod '
curl -sSf -o eval/diff/cases/C/LICENSE https://raw.githubusercontent.com/<owner>/<repo>/<tag>/LICENSE
```

- The Lean surface has one caller, `Main.lean`. No other Lake project requires `eval/diff`.

### The parser this run compares against

Strict. `go mod edit -json` calls `modfile.Parse` (Go 1.24.7, `src/cmd/go/internal/modcmd/edit.go`
line 248), the parser that reads a module's own go.mod. Each pin is its module's own go.mod, so
this is the parser that reads it in its own repository. cmd/go reads a dependency's go.mod with
`modfile.ParseLax` instead (`modload/modfile.go` line 699, `modfetch/coderepo.go` line 1038).
`parseToFile` (`vendor/golang.org/x/mod/modfile/rule.go` lines 286 to 296, 331 to 344) shows what
lax does differently:

| A file strict Go rejects, with | Lax Go | The model | Facts differ? |
|---|---|---|---|
| a block opener with more than one token, `require a (` | skips the block | `requires a`, then reads the block's lines at top level, where they are unread | yes, the model has `a` (F3) |
| an unknown directive or block, such as `ignore` before Go 1.25 | skips it | reads it as unread | no |
| a malformed `replace`, `exclude`, `toolchain`, `godebug` or `tool` line | skips it | reads it as unread | no |
| a `go` version that lax repairs | keeps it | reads it as unread | no |

So the lax-only difference is the first row, and the strict run never meets it, because strict Go
rejects that file: Go 1.24.7 prints `unknown block type: require a`. The #272 verifier found 141
fuzzed files of this kind (#209). Three readers on one file, measured (F3), are the guard's text:
`laxBlockOpener` in `Diff/Plugin.lean` pins the model's reading, so a model PR that changes it
fails this build, and that PR updates this paragraph. The report says "strict parser
`modfile.Parse`" in its second line, and deferrals list the lax case.

### How a builder goes wrong here

- A vendored file named `go.mod`. GitHub's dependency graph reads files with that name (A8) and
  would raise alerts on other projects' dependencies, and Go run inside a case directory would take
  it for a module and obey its `go` and `toolchain` lines. The files are `module.mod` and
  `module.json`.
- `go mod edit` run with the caller's Go settings. Under `GOTOOLCHAIN=auto`, the `go` and
  `toolchain` lines of a go.mod in or above the working directory select, and download, another
  Go. `Diff.Go.runGo` sets `GOTOOLCHAIN=local`, `GOWORK=off`, `GOFLAGS=` and `GOENV=off`, and
  runs in `/`, outside every module. Keep all five.
- Comparing as sets, the gate's view (#282). `compare_eq_nil` then has no proof (M1).
- A `match` on `FactKind` with only `provides` and `requires`. It stops compiling when P2-001b adds
  `binds` (#285 item 6). `Keys.ofFacts` filters with `==`, and check 2 greps for the name.
- `Keys.ofPlugin_eq_model` dropped because nothing calls it. It is the only line outside
  `examples/` that names `GoMod.run_eq`, so it is what breaks this build when a plugin change drops
  `run_eq` (W2). Reading `Models.GoMod.facts` in place of the extractor breaks it too (M5): the
  run must exercise the compiled plugin.
- A `module.json` written by hand, by `jq`, or by a Go other than `.go-version`'s. `--refresh`
  refuses another Go (T9), and check 7 shows any byte that differs from Go's.
- An edited `module.mod`. `check-pins.sh` hashes each one against `pins.tsv` (T13).
- `lake build` at the root taken for the check. The root project does not include `eval/`. Run
  `lake --dir eval/diff build`. `warningAsError` makes a `sorry` or a deprecation an error here, as
  in `eval/mutants`, unlike `examples/acme`.
- An IO error left to escape `main`. Lean then exits 1, which reads as "untriaged mismatch".
  `main` catches it and exits 2 (T6).
- A proxy URL for a module path with an upper-case letter. The proxy escapes each one as `!` and
  the lower-case letter. All 13 pins are lower case, and `check-pins.sh` refuses the rest.
- A licence from the wrong place. It is the repository's root file at the version's tag. gopls
  has no `gopls/LICENSE` at `gopls/v0.24.0` (404); the golang/tools root `LICENSE` covers it.
- Deleting a triage line to get a green run, or adding one with an invented issue number. A needed
  line's absence is exit 1, a line that matches nothing is exit 1 (T4), and the verifier opens each
  issue number in `triage.tsv` (check 12).
- The design-time placeholder `#<n>` in `triage.tsv`. The two lines cite the existing quoted-path
  issue #328 (S2).
- Letting git rewrite line endings under `cases/`. `cases/.gitattributes` holds `* -text`.
- A comment in a Lean file or a script. The usage string is the runner's help, and the statements
  and fixtures carry the rules.

types:

`eval/diff/lakefile.toml`:

```toml
name = "mitos-diff"
defaultTargets = ["mitos-diff"]

[leanOptions]
warningAsError = true

[[require]]
name = "acme"
path = "../../examples/acme"

[[lean_lib]]
name = "Diff"
globs = ["Diff.+"]

[[lean_exe]]
name = "mitos-diff"
root = "Main"
```

`eval/diff/lean-toolchain`:

```text
leanprover/lean4:v4.35.0
```

`eval/diff/.go-version`:

```text
1.24.7
```

`eval/diff/cases/.gitattributes`:

```text
* -text
```

`eval/diff/pins.tsv`, tab-separated:

```text
# case	module	version	go.mod hash (as go.sum and sum.golang.org print it)	repository	licence (SPDX)
argo-cd	github.com/argoproj/argo-cd/v3	v3.6.1	h1:DUcIODAWqGVX6xq1xX4fSWxrPoLGwmdg6goKjEUp4P8=	https://github.com/argoproj/argo-cd	Apache-2.0
cobra	github.com/spf13/cobra	v1.10.2	h1:7C1pvHqHw5A4vrJfjNwvOdzYu0Gml16OCs2GRiTUUS4=	https://github.com/spf13/cobra	Apache-2.0
etcd	go.etcd.io/etcd/v3	v3.7.3	h1:r2qRGHG1R+ShYe3BdDnxBRGLN0MouUagLt39lhPDxrw=	https://github.com/etcd-io/etcd	Apache-2.0
gh-cli	github.com/cli/cli/v2	v2.104.0	h1:lddfsaCvL72knAc/M7mR0N3N4nSU3X92MPCZepXm4Wc=	https://github.com/cli/cli	MIT
go-redis	github.com/redis/go-redis/v9	v9.23.0	h1:EWP2UUk+XDaI1s5nQB5mablZN6vccXlmBQTyfnF87D0=	https://github.com/redis/go-redis	BSD-2-Clause
gopls	golang.org/x/tools/gopls	v0.24.0	h1:abHXJMs6FnwH1z/R1GrYVo/TBfxyDbSFMCKakBQURg0=	https://github.com/golang/tools	BSD-3-Clause
grpc	google.golang.org/grpc	v1.85.0	h1:0rQrOD58yjal/0EaVbGBANindixsCZNQPDV3VKtaKuQ=	https://github.com/grpc/grpc-go	Apache-2.0
kubernetes	k8s.io/kubernetes	v1.37.2	h1:zAK7e3i5feyBL/bhucQnA5VRKuyrS8F+ijHJkZzQaWw=	https://github.com/kubernetes/kubernetes	Apache-2.0
prometheus	github.com/prometheus/prometheus	v0.316.0	h1:nd2m0IehYLgxV4yAmoQDsvV45I9Xerh+uTUeCioEMis=	https://github.com/prometheus/prometheus	Apache-2.0
rsc-quote	rsc.io/quote	v1.5.2	h1:LzX7hefJvL54yjefDEDHNONDjII0t9xZLPXsUe+TKr0=	https://github.com/rsc/quote	BSD-3-Clause
tailscale	tailscale.com	v1.104.7	h1:pNl682NgUoac2/Um3khv8pduX3D1YPBZTL067+zo8wY=	https://github.com/tailscale/tailscale	BSD-3-Clause
traefik	github.com/traefik/traefik/v3	v3.7.19	h1:cWOaosHycDsgqDQ3goeY6UxE47EfJ74aDFwwgsFy5wY=	https://github.com/traefik/traefik	MIT
zap	go.uber.org/zap	v1.28.0	h1:rDLpOi171uODNm/mxFcuYWxDsqWSAVkFdX4XojSKg/Q=	https://github.com/uber-go/zap	MIT
```

`eval/diff/licences.tsv`, tab-separated. These reviewed source URLs, SPDX claims and exact bytes
bind the licence decision to each module version. A builder verifies the licence grant and notices
at each source before accepting or changing a row; a hash preserves that review, not a legal
classification inferred by the checker. An absent or ambiguous grant still stops at S3.

```text
# case	module	version	licence (SPDX)	LICENSE URL	LICENSE SHA256	NOTICE URL (- if none)	NOTICE SHA256 (- if none)
argo-cd	github.com/argoproj/argo-cd/v3	v3.6.1	Apache-2.0	https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/LICENSE	c996fc213c94f4a4a838407d355b081226caa7b103a4f239bb87fb8f1d8e3a60	-	-
cobra	github.com/spf13/cobra	v1.10.2	Apache-2.0	https://raw.githubusercontent.com/spf13/cobra/v1.10.2/LICENSE.txt	5e3400b93bbb099e83e52bab885e7441750673c21f97988ca3f1240639b63283	-	-
etcd	go.etcd.io/etcd/v3	v3.7.3	Apache-2.0	https://raw.githubusercontent.com/etcd-io/etcd/v3.7.3/LICENSE	43ca1b4bbf462789ba15b28373e0c536e510f49e4d05d85a7690cfee94de6f49	-	-
gh-cli	github.com/cli/cli/v2	v2.104.0	MIT	https://raw.githubusercontent.com/cli/cli/v2.104.0/LICENSE	6da4adc42392c8485e40b4251c7e332fc3352df1947c9ffade71dd60b14a7a4f	-	-
go-redis	github.com/redis/go-redis/v9	v9.23.0	BSD-2-Clause	https://raw.githubusercontent.com/redis/go-redis/v9.23.0/LICENSE	a3a7dff87da3927db65cb4c87b1cfbc96ca2755704461a485d457be7ae300a86	-	-
gopls	golang.org/x/tools/gopls	v0.24.0	BSD-3-Clause	https://raw.githubusercontent.com/golang/tools/gopls/v0.24.0/LICENSE	911f8f5782931320f5b8d1160a76365b83aea6447ee6c04fa6d5591467db9dad	-	-
grpc	google.golang.org/grpc	v1.85.0	Apache-2.0	https://raw.githubusercontent.com/grpc/grpc-go/v1.85.0/LICENSE	cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30	https://raw.githubusercontent.com/grpc/grpc-go/v1.85.0/NOTICE.txt	693ff28ec216d5112ac1bbfe64ef539005867d1c7bd427b57d579683293b947f
kubernetes	k8s.io/kubernetes	v1.37.2	Apache-2.0	https://raw.githubusercontent.com/kubernetes/kubernetes/v1.37.2/LICENSE	cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30	-	-
prometheus	github.com/prometheus/prometheus	v0.316.0	Apache-2.0	https://raw.githubusercontent.com/prometheus/prometheus/v0.316.0/LICENSE	c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4	https://raw.githubusercontent.com/prometheus/prometheus/v0.316.0/NOTICE	ac9e304462a58a4d71b6488423d4447e614c8b31d517fe24345016522c102a78
rsc-quote	rsc.io/quote	v1.5.2	BSD-3-Clause	https://raw.githubusercontent.com/rsc/quote/v1.5.2/LICENSE	2d36597f7117c38b006835ae7f537487207d8ec407aa9d9980794b2030cbc067	-	-
tailscale	tailscale.com	v1.104.7	BSD-3-Clause	https://raw.githubusercontent.com/tailscale/tailscale/v1.104.7/LICENSE	a7ca6186a7963a0a60740f6047760eecd7a0234e8c38bd7e1e0bbcb324bda45b	-	-
traefik	github.com/traefik/traefik/v3	v3.7.19	MIT	https://raw.githubusercontent.com/traefik/traefik/v3.7.19/LICENSE.md	c33e29340498ccde22ba0ab9537d6eb0aa3a2eae0dda61bb6df31df6a032fa5b	-	-
zap	go.uber.org/zap	v1.28.0	MIT	https://raw.githubusercontent.com/uber-go/zap/v1.28.0/LICENSE	c2b97b3281be272711909076c8402499b4b5a3216196af47a25b1d3674d86152	-	-
```

`eval/diff/triage.tsv`, where `#<n>` is the issue of S2 (a builder writes the number; the sketch
was built with `#999`):

```
# case	mismatch	directive	path	issue
rsc-quote	only-in-go	module	rsc.io/quote	#<n>
rsc-quote	only-in-go	require	rsc.io/sampler	#<n>
```

The vendored files, fetched once by the builder with `cd eval/diff` first (then `--refresh` writes
each `module.json`). The run of these commands in a scratch folder gave 28 files, byte for byte the
committed ones (Evidence):

```bash
grep -v '^#' pins.tsv | while IFS=$'\t' read -r c m v h r l; do
  mkdir -p "cases/$c"
  curl -sSf --retry 3 -o "cases/$c/module.mod" "https://proxy.golang.org/$m/@v/$v.mod"
done
while read -r c url name; do curl -sSf --retry 3 -o "cases/$c/$name" "$url"; done <<'LIST'
argo-cd https://raw.githubusercontent.com/argoproj/argo-cd/v3.6.1/LICENSE LICENSE
cobra https://raw.githubusercontent.com/spf13/cobra/v1.10.2/LICENSE.txt LICENSE
etcd https://raw.githubusercontent.com/etcd-io/etcd/v3.7.3/LICENSE LICENSE
gh-cli https://raw.githubusercontent.com/cli/cli/v2.104.0/LICENSE LICENSE
go-redis https://raw.githubusercontent.com/redis/go-redis/v9.23.0/LICENSE LICENSE
gopls https://raw.githubusercontent.com/golang/tools/gopls/v0.24.0/LICENSE LICENSE
grpc https://raw.githubusercontent.com/grpc/grpc-go/v1.85.0/LICENSE LICENSE
grpc https://raw.githubusercontent.com/grpc/grpc-go/v1.85.0/NOTICE.txt NOTICE
kubernetes https://raw.githubusercontent.com/kubernetes/kubernetes/v1.37.2/LICENSE LICENSE
prometheus https://raw.githubusercontent.com/prometheus/prometheus/v0.316.0/LICENSE LICENSE
prometheus https://raw.githubusercontent.com/prometheus/prometheus/v0.316.0/NOTICE NOTICE
rsc-quote https://raw.githubusercontent.com/rsc/quote/v1.5.2/LICENSE LICENSE
tailscale https://raw.githubusercontent.com/tailscale/tailscale/v1.104.7/LICENSE LICENSE
traefik https://raw.githubusercontent.com/traefik/traefik/v3.7.19/LICENSE.md LICENSE
zap https://raw.githubusercontent.com/uber-go/zap/v1.28.0/LICENSE LICENSE
LIST
```

- Lean files have no `deriving` limits here: `eval/diff` is evaluation code, not a model, and gate
  1 does not read it. `Directive`, `Keys`, `Side`, `Mismatch` and `Finding` derive `DecidableEq`,
  so the theorems compare them and `decide +kernel` runs on them.
- `Keys` holds the two ordered lists Go prints, `Module.Path` and `Require[].Path`. A plugin fact
  of kind `provides` is a module key, of kind `requires` a require key, in the plugin's order.
  Versions are not read (the plan's subset), and a fact's span is proved anchored by the plugin, so
  keys are all there is to compare. An empty `Module.Path` means no `module` line, so no key.
- A `Mismatch` is a path only Go has or only the plugin has (`onlyIn`, repeats counted), or the
  shared paths in another order (`order`). `Finding` adds the case. `Triage` adds the issue. A triage
  line covers every occurrence of its mismatch.
- An `UnreadLine` is a 1-based line number and the line's text, for each line the model reads as
  `Reading.unread`. The opener and the closer of a block the model does not read (`replace (`,
  `)`) are block structure, which the model tracks; the lines inside are listed.

`eval/diff/Diff/Compare.lean`:

```lean
namespace Diff

inductive Directive where
  | module
  | require
  deriving DecidableEq, Repr

structure Keys where
  modules : List String
  requires : List String
  deriving DecidableEq, Repr

inductive Side where
  | plugin
  | go
  deriving DecidableEq, Repr

inductive Mismatch where
  | onlyIn (side : Side) (directive : Directive) (path : String)
  | order (directive : Directive)
  deriving DecidableEq, Repr

def unmatched (xs ys : List String) : List String := ys.foldl List.erase xs

def shared (xs ys : List String) : List String :=
  (unmatched xs.reverse (unmatched xs ys)).reverse

def compareList (directive : Directive) (plugin go : List String) : List Mismatch :=
  if plugin = go then []
  else
    let onlyGo := unmatched go plugin
    let onlyPlugin := unmatched plugin go
    if onlyGo.isEmpty && onlyPlugin.isEmpty then [.order directive]
    else onlyGo.map (.onlyIn .go directive) ++ onlyPlugin.map (.onlyIn .plugin directive) ++
      if shared plugin go = shared go plugin then [] else [.order directive]

def compare (plugin go : Keys) : List Mismatch :=
  compareList .module plugin.modules go.modules ++
    compareList .require plugin.requires go.requires

theorem compareList_eq_nil {directive : Directive} {plugin go : List String} :
    compareList directive plugin go = [] ↔ plugin = go := by
  unfold compareList
  by_cases h : plugin = go
  · simp [h]
  · simp only [h, ite_false, iff_false]
    split
    · exact List.cons_ne_nil _ _
    · rename_i hne
      intro hnil
      simp only [List.append_eq_nil_iff, List.map_eq_nil_iff] at hnil
      simp [hnil.1.1, hnil.1.2] at hne

theorem compare_eq_nil {plugin go : Keys} : compare plugin go = [] ↔ plugin = go := by
  rw [compare, List.append_eq_nil_iff, compareList_eq_nil, compareList_eq_nil]
  cases plugin
  cases go
  simp

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["a", "b"]⟩ == []

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["b", "a"]⟩ == [.order .require]

#guard compare ⟨["m"], ["a"]⟩ ⟨["m"], ["a", "a"]⟩ == [.onlyIn .go .require "a"]

#guard compare ⟨[], ["a"]⟩ ⟨[","], ["a"]⟩ == [.onlyIn .go .module ","]

#guard compare ⟨["m"], ["a", "x"]⟩ ⟨["m"], ["a", "y"]⟩ ==
  [.onlyIn .go .require "y", .onlyIn .plugin .require "x"]

#guard compare ⟨["m"], ["a", "b"]⟩ ⟨["m"], ["b", "a", "c"]⟩ ==
  [.onlyIn .go .require "c", .order .require]

#guard compare ⟨["m"], ["a", "b", "x"]⟩ ⟨["m"], ["b", "a", "c"]⟩ ==
  [.onlyIn .go .require "c", .onlyIn .plugin .require "x", .order .require]

#guard compare ⟨["m"], ["a", "b", "a"]⟩ ⟨["m"], ["a", "b"]⟩ ==
  [.onlyIn .plugin .require "a"]

end Diff
```

`eval/diff/Diff/Pins.lean`:

```lean
namespace Diff

structure Pin where
  case : String
  module : String
  version : String
  goModHash : String
  repository : String
  licence : String

def parsePins (text : String) : Except String (List Pin) := do
  let mut out := #[]
  let mut n := 0
  for line in text.splitOn "\n" do
    n := n + 1
    if line.isEmpty || line.startsWith "#" then continue
    match line.splitOn "\t" with
    | [case, module, version, goModHash, repository, licence] =>
      if out.any (·.case == case) then throw s!"pins.tsv:{n}: case {case} listed twice"
      out := out.push { case, module, version, goModHash, repository, licence }
    | fields => throw s!"pins.tsv:{n}: expected 6 tab-separated fields, found {fields.length}"
  return out.toList

end Diff
```

`eval/diff/Diff/Go.lean`:

```lean
import Lean.Data.Json
import Diff.Compare
import Diff.Pins

namespace Diff

open Lean (Json)

def Keys.ofGoJson (text : String) : Except String Keys := do
  let json ← Json.parse text
  let module ← json.getObjVal? "Module"
  let modulePath ← module.getObjValAs? String "Path"
  let requires ← match json.getObjValD "Require" with
    | .null => pure #[]
    | value => value.getArr?
  let requirePaths ← requires.mapM (·.getObjValAs? String "Path")
  return { modules := if modulePath.isEmpty then [] else [modulePath],
           requires := requirePaths.toList }

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"\"}, \"Require\": null}").toOption == some ⟨[], []⟩

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"m\"}, \"Require\": [{\"Path\": \"a\"}, {\"Path\": \"b\", \"Indirect\": true}]}").toOption == some ⟨["m"], ["a", "b"]⟩

#guard (Keys.ofGoJson "{\"Require\": []}").toOption.isNone

#guard (Keys.ofGoJson "{\"Module\": {\"Path\": \"m\"}, \"Require\": 3}").toOption.isNone

def goEnv : Array (String × Option String) :=
  #[("GOTOOLCHAIN", some "local"), ("GOWORK", some "off"), ("GOFLAGS", some ""),
    ("GOENV", some "off")]

def runGo (args : Array String) : IO IO.Process.Output :=
  IO.Process.output { cmd := "go", args, env := goEnv, cwd := some "/" }

def refresh (cases : System.FilePath) (goVersion : String) (pins : List Pin) : IO Bool := do
  let version ← runGo #["env", "GOVERSION"]
  unless version.exitCode == 0 && version.stdout.trimAscii.toString == goVersion do
    IO.eprintln s!"--refresh needs {goVersion}; `go env GOVERSION` printed {repr version.stdout.trimAscii.toString}"
    return false
  let mut ok := true
  for p in pins do
    let modFile ← IO.FS.realPath (cases / p.case / "module.mod")
    let out ← runGo #["mod", "edit", "-json", modFile.toString]
    if out.exitCode == 0 then IO.FS.writeFile (cases / p.case / "module.json") out.stdout
    else
      IO.eprintln s!"{p.case}: {goVersion} rejects {p.module}@{p.version}: {out.stderr.trimAscii.toString}"
      ok := false
  return ok

end Diff
```

`eval/diff/Diff/Plugin.lean`:

```lean
import Mitos.Core
import Models.GoMod
import Models.GoMod.Examples
import Plugins.GoMod
import Diff.Compare

namespace Diff

open Mitos

def Keys.ofFacts (facts : List Fact) : Keys where
  modules := (facts.filter (·.kind == .provides)).map (·.ident.key)
  requires := (facts.filter (·.kind == .requires)).map (·.ident.key)

def Keys.ofPlugin (text : String) : Keys := Keys.ofFacts (GoMod.extractor.run text)

theorem Keys.ofPlugin_eq_model (text : String) :
    Keys.ofPlugin text = Keys.ofFacts (Models.GoMod.facts text) := by
  rw [Keys.ofPlugin, GoMod.run_eq]

structure UnreadLine where
  number : Nat
  text : String

theorem readingsFrom_offsets (mode : Models.GoMod.Mode) (ls : List (Nat × List Char)) :
    (Models.GoMod.readingsFrom mode ls).map Prod.fst = ls.map Prod.fst := by
  induction ls generalizing mode with
  | nil => rfl
  | cons line rest ih =>
    rw [Models.GoMod.readingsFrom]
    rcases mode.step line with ⟨next, reading⟩
    simp only [List.map_cons, ih]

theorem readings_offsets (text : String) :
    (Models.GoMod.readings text).map Prod.fst = (lines text.toList).map Prod.fst :=
  readingsFrom_offsets _ _

def unreadLines (text : String) : List UnreadLine :=
  ((lines text.toList).zip (Models.GoMod.readings text)).zipIdx.filterMap
    fun ((line, _, reading), index) =>
      match reading with
      | .unread => some { number := index + 1, text := String.ofList line.2 }
      | _ => none

theorem ofPlugin_wholeFile :
    Keys.ofPlugin Models.GoMod.wholeFile.file =
      { modules := ["example.com/app"], requires := ["example.com/lib", "example.com/util"] } := by
  rw [Keys.ofPlugin_eq_model]
  decide +kernel

theorem unreadLines_wholeFile :
    (unreadLines Models.GoMod.wholeFile.file).map (fun l => (l.number, l.text)) =
      [(3, "go 1.22"), (11, "replace example.com/lib => ../lib")] := by
  decide +kernel

def laxBlockOpener : String :=
  "module example.com/app\nrequire a (\n\tb v1.0.0\n)\nrequire c/d v1.0.0\n"

#guard Keys.ofPlugin laxBlockOpener == ⟨["example.com/app"], ["a", "c/d"]⟩

#guard Keys.ofPlugin "require example.com/lib v1.2.0\n" == ⟨[], ["example.com/lib"]⟩

end Diff
```

`eval/diff/Diff/Triage.lean`:

```lean
import Diff.Compare

namespace Diff

def Directive.name : Directive → String
  | .module => "module"
  | .require => "require"

def Directive.ofName : String → Option Directive
  | "module" => some .module
  | "require" => some .require
  | _ => none

structure Finding where
  case : String
  mismatch : Mismatch
  deriving DecidableEq, Repr

def Finding.fields : Finding → List String
  | ⟨case, .onlyIn .go directive path⟩ => [case, "only-in-go", directive.name, path]
  | ⟨case, .onlyIn .plugin directive path⟩ => [case, "only-in-plugin", directive.name, path]
  | ⟨case, .order directive⟩ => [case, "order", directive.name, "-"]

def Finding.ofFields : List String → Option Finding
  | [case, "only-in-go", directive, path] =>
    (Directive.ofName directive).map fun d => ⟨case, .onlyIn .go d path⟩
  | [case, "only-in-plugin", directive, path] =>
    (Directive.ofName directive).map fun d => ⟨case, .onlyIn .plugin d path⟩
  | [case, "order", directive, "-"] =>
    (Directive.ofName directive).map fun d => ⟨case, .order d⟩
  | _ => none

theorem Finding.ofFields_fields (f : Finding) : Finding.ofFields f.fields = some f := by
  rcases f with ⟨case, ⟨side, directive, path⟩ | directive⟩ <;>
    (try cases side) <;> cases directive <;> rfl

structure Triage where
  finding : Finding
  issue : Nat

def parseTriage (text : String) : Except String (List Triage) := do
  let mut out := #[]
  let mut n := 0
  for line in text.splitOn "\n" do
    n := n + 1
    if line.isEmpty || line.startsWith "#" then continue
    let fields := line.splitOn "\t"
    let some finding := Finding.ofFields fields.dropLast
      | throw s!"triage.tsv:{n}: expected a case, a mismatch and an issue, found {repr fields}"
    let some issue := (fields.getLast?.getD "").dropPrefix? "#" |>.bind (·.toString.toNat?)
      | throw s!"triage.tsv:{n}: the last field is not an issue such as #123"
    out := out.push { finding, issue }
  return out.toList

def Triage.issuesFor (triage : List Triage) (f : Finding) : List Nat :=
  (triage.filter (·.finding == f)).map (·.issue)

end Diff
```

`eval/diff/Diff/Report.lean`:

```lean
import Diff.Compare
import Diff.Plugin
import Diff.Triage

namespace Diff

structure CaseReport where
  case : String
  module : String
  version : String
  pluginKeys : Keys
  goKeys : Keys
  unread : List UnreadLine

def CaseReport.findings (r : CaseReport) : List Finding :=
  (compare r.pluginKeys r.goKeys).map (⟨r.case, ·⟩)

def findings (reports : List CaseReport) : List Finding := reports.flatMap (·.findings)

structure Verdict where
  untriaged : List Finding
  stale : List Triage

def verdict (reports : List CaseReport) (triage : List Triage) : Verdict where
  untriaged := (findings reports).filter fun f => (Triage.issuesFor triage f).isEmpty
  stale := triage.filter fun t => !(findings reports).contains t.finding

def Verdict.clean (v : Verdict) : Bool := v.untriaged.isEmpty && v.stale.isEmpty

theorem verdict_clean {reports : List CaseReport} {triage : List Triage} :
    (verdict reports triage).clean = true ↔
      (∀ f ∈ findings reports, ∃ t ∈ triage, t.finding = f) ∧
      (∀ t ∈ triage, t.finding ∈ findings reports) := by
  simp [Verdict.clean, verdict, Triage.issuesFor, List.filter_eq_nil_iff]

def Mismatch.describe : Mismatch → String
  | .onlyIn .go directive path => s!"{directive.name} `{path}`: only in Go"
  | .onlyIn .plugin directive path => s!"{directive.name} `{path}`: only in the plugin"
  | .order directive => s!"{directive.name}: shared paths in another order"

def Keys.count (k : Keys) : Nat := k.modules.length + k.requires.length

def tsv (fields : List String) : String := s!"`{String.intercalate "\t" fields}`"

def render (goVersion : String) (reports : List CaseReport) (triage : List Triage) : String :=
  Id.run do
    let v := verdict reports triage
    let mut out := "## go.mod differential run\n\n"
    out := out ++ s!"`GoMod.extractor` against `go mod edit -json` of {goVersion}, which reads "
    out := out ++ s!"each file with the strict parser `modfile.Parse`. {reports.length} pinned modules.\n\n"
    out := out ++ "| Case | Module | Plugin facts | Go facts | Mismatches | Triaged | Lines outside the subset |\n"
    out := out ++ "|---|---|---|---|---|---|---|\n"
    for r in reports do
      let fs := r.findings
      let triaged := fs.filter fun f => !(Triage.issuesFor triage f).isEmpty
      out := out ++ s!"| {r.case} | `{r.module}@{r.version}` | {r.pluginKeys.count} | {r.goKeys.count} "
      out := out ++ s!"| {fs.length} | {triaged.length} | {r.unread.length} |\n"
    out := out ++ "\n"
    if v.untriaged.isEmpty then out := out ++ "Untriaged mismatches: none.\n"
    else
      out := out ++ "Untriaged mismatches, as `triage.tsv` lines with the issue to fill in:\n"
      for f in v.untriaged do out := out ++ s!"- {tsv (f.fields ++ ["#?"])}\n"
    if v.stale.isEmpty then out := out ++ "Stale triage lines: none.\n"
    else
      out := out ++ "Stale triage lines, which match no mismatch:\n"
      for t in v.stale do out := out ++ s!"- {tsv (t.finding.fields ++ [s!"#{t.issue}"])}\n"
    for r in reports do
      out := out ++ s!"\n### {r.case}\n\n"
      if r.findings.isEmpty then out := out ++ "No mismatch.\n"
      for f in r.findings do
        let issues := (Triage.issuesFor triage f).map (s!"#{·}")
        let status := if issues.isEmpty then "untriaged" else String.intercalate ", " issues
        out := out ++ s!"- {f.mismatch.describe} ({status})\n"
      if r.unread.isEmpty then out := out ++ "\nNo line outside the subset.\n"
      else
        out := out ++ "\nLines outside the subset:\n\n"
        for l in r.unread do out := out ++ s!"- {l.number}: `{l.text}`\n"
    return out

end Diff
```

`eval/diff/Main.lean`:

```lean
import Diff.Go
import Diff.Pins
import Diff.Plugin
import Diff.Report
import Diff.Triage

open Diff

def usage : String := "usage: mitos-diff <dir> [--refresh]
  <dir>/.go-version               the Go release of every module.json, as actions/setup-go reads it
  <dir>/pins.tsv                  case, module, version, go.mod hash, repository, licence
  <dir>/triage.tsv                case, mismatch, issue: the mismatches a model issue explains
  <dir>/cases/<case>/module.mod   the pinned go.mod, as proxy.golang.org serves it
  <dir>/cases/<case>/module.json  `go mod edit -json` of it
Prints the report as Markdown. Exit 0 when every mismatch is triaged and every triage line
matches one, 1 when not, 2 on bad input. --refresh first rewrites each module.json with the Go
release that .go-version names."

def caseDirs (cases : System.FilePath) : IO (List String) := do
  let mut out := #[]
  for e in ← cases.readDir do
    if ← e.path.isDir then out := out.push e.fileName
  return out.toList.mergeSort (· ≤ ·)

def report (cases : System.FilePath) (p : Pin) : ExceptT String IO CaseReport := do
  let text ← IO.FS.readFile (cases / p.case / "module.mod")
  let json ← IO.FS.readFile (cases / p.case / "module.json")
  match Keys.ofGoJson json with
  | .error e => throw s!"{p.case}/module.json: {e}"
  | .ok goKeys =>
    return { case := p.case, module := p.module, version := p.version, goKeys,
             pluginKeys := Keys.ofPlugin text, unread := unreadLines text }

def run (dir : System.FilePath) (withRefresh : Bool) : ExceptT String IO UInt32 := do
  let goVersion := "go" ++ (← IO.FS.readFile (dir / ".go-version")).trimAscii.toString
  let pins ← liftExcept <| parsePins (← IO.FS.readFile (dir / "pins.tsv"))
  let triage ← liftExcept <| parseTriage (← IO.FS.readFile (dir / "triage.tsv"))
  let cases := dir / "cases"
  let dirs ← caseDirs cases
  let listed := (pins.map (·.case)).mergeSort (· ≤ ·)
  unless dirs == listed do
    throw s!"cases/ holds {dirs}, pins.tsv lists {listed}"
  if withRefresh then
    unless ← refresh cases goVersion pins do return 2
  let mut reports := #[]
  for p in pins do
    reports := reports.push (← report cases p)
  IO.print (render goVersion reports.toList triage)
  return if (verdict reports.toList triage).clean then 0 else 1
where
  liftExcept {α} : Except String α → ExceptT String IO α := fun e => ExceptT.mk (pure e)

def main (args : List String) : IO UInt32 := do
  let (dir, withRefresh) ← match args with
    | [dir] => pure (dir, false)
    | [dir, "--refresh"] => pure (dir, true)
    | _ => do IO.eprintln usage; return 2
  try
    match ← (run dir withRefresh).run with
    | .ok code => return code
    | .error e => IO.eprintln e; return 2
  catch e =>
    IO.eprintln e
    return 2
```

`eval/diff/check-pins.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
online=false
case "${1:-}" in
  "") ;;
  --online) online=true ;;
  *) echo "usage: check-pins.sh [--online]" >&2; exit 2 ;;
esac
for tool in sha256sum openssl base64; do
  command -v "$tool" > /dev/null || { echo "check-pins.sh: needs $tool" >&2; exit 2; }
done
if $online && ! command -v curl > /dev/null; then
  echo "check-pins.sh: --online needs curl" >&2
  exit 2
fi
status=0
problem() { echo "$1: $2" >&2; status=1; }
[ -r pins.tsv ] || { echo "check-pins.sh: cannot read pins.tsv" >&2; exit 2; }
[ -r licences.tsv ] || { echo "check-pins.sh: cannot read licences.tsv" >&2; exit 2; }
declare -A modules versions spdx licence_urls licence_hashes notice_urls notice_hashes used
while IFS=$'\t' read -r c m v l lu lh nu nh extra || [ -n "$c" ]; do
  case $c in ''|'#'*) continue ;; esac
  case $c in *[!a-zA-Z0-9_-]*) echo "check-pins.sh: bad licence case $c" >&2; exit 2 ;; esac
  if [ -n "${modules[$c]+listed}" ] || [ -n "$extra" ] ||
      [ -z "$m" ] || [ -z "$v" ] || [ -z "$l" ] ||
      [ -z "$lu" ] || [ -z "$lh" ] || [ -z "$nu" ] || [ -z "$nh" ]; then
    echo "check-pins.sh: malformed or duplicate licence row for $c" >&2; exit 2
  fi
  modules[$c]=$m; versions[$c]=$v; spdx[$c]=$l
  licence_urls[$c]=$lu; licence_hashes[$c]=$lh; notice_urls[$c]=$nu; notice_hashes[$c]=$nh
done < licences.tsv
check_source() {
  local c=$1 name=$2 url=$3 hash=$4 actual
  if [ ! -s "cases/$c/$name" ]; then problem "$c" "no $name"; return; fi
  actual=$(sha256sum < "cases/$c/$name" | cut -d' ' -f1)
  [ "$actual" = "$hash" ] || problem "$c" "$name differs from reviewed source $url"
  if $online; then
    if actual=$(curl -sSf --retry 3 "$url" | sha256sum | cut -d' ' -f1); then
      [ "$actual" = "$hash" ] || problem "$c" "$name source differs from reviewed hash: $url"
    else problem "$c" "cannot fetch $name source: $url"; fi
  fi
}
count=0
while IFS=$'\t' read -r c m v h _ l || [ -n "$c" ]; do
  case $c in ''|'#'*) continue ;; esac
  case $c in *[!a-zA-Z0-9_-]*) echo "check-pins.sh: bad pin case $c" >&2; exit 2 ;; esac
  count=$((count + 1))
  if [ -z "${modules[$c]+listed}" ]; then problem "$c" "no reviewed licence row"; continue; fi
  used[$c]=yes
  if [ "$m" != "${modules[$c]}" ] || [ "$v" != "${versions[$c]}" ] || [ "$l" != "${spdx[$c]}" ]; then
    problem "$c" "pin does not match reviewed licence metadata"
  fi
  f=cases/$c/module.mod
  if [ ! -f "$f" ]; then problem "$c" "no module.mod"; continue; fi
  got="h1:$(printf '%s  go.mod\n' "$(sha256sum < "$f" | cut -d' ' -f1)" | openssl dgst -sha256 -binary | base64)"
  [ "$got" = "$h" ] || problem "$c" "pins.tsv says $h, module.mod hashes to $got"
  if $online; then
    sum=$(curl -sSf --retry 3 "https://sum.golang.org/lookup/$m@$v" | grep -F "$m $v/go.mod " | cut -d' ' -f3)
    [ "$sum" = "$h" ] || problem "$c" "pins.tsv says $h, sum.golang.org says $sum"
  fi
  check_source "$c" LICENSE "${licence_urls[$c]}" "${licence_hashes[$c]}"
  if [ "${notice_urls[$c]}" != - ]; then
    check_source "$c" NOTICE "${notice_urls[$c]}" "${notice_hashes[$c]}"
  elif [ "${notice_hashes[$c]}" != - ]; then
    problem "$c" "NOTICE hash without a source URL"
  fi
  case $l in
    Apache-2.0|BSD-2-Clause|BSD-3-Clause|MIT) ;;
    *) problem "$c" "licence $l is not one of the four the design allows; the owner decides" ;;
  esac
  case $m in
    *[A-Z]*) problem "$c" "module path has an upper-case letter, which the proxy escapes" ;;
  esac
done < pins.tsv
[ "$count" -gt 0 ] || { echo "check-pins.sh: pins.tsv has no pins" >&2; exit 2; }
for c in "${!modules[@]}"; do
  [ -n "${used[$c]+checked}" ] || problem "$c" "reviewed licence row has no pin"
done
exit "$status"
```

`eval/diff/selftest.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
d=$tmp/d
okmod=$'module example.com/app\n\nrequire example.com/lib v1.2.0\n'
okjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/lib","Version":"v1.2.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
quotedmod=$'module example.com/app\n\nrequire (\n\texample.com/lib v1.2.0\n)\n\nrequire "example.com/q" v1.2.0\n'
quotedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/lib","Version":"v1.2.0"},{"Path":"example.com/q","Version":"v1.2.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
pairmod=$'module example.com/app\n\nrequire (\n\texample.com/a v1.0.0\n\texample.com/b v1.0.0\n)\n'
swappedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/b","Version":"v1.0.0"},{"Path":"example.com/a","Version":"v1.0.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'

fresh() {
  rm -rf "$d"
  mkdir -p "$d/cases"
  echo 1.24.7 > "$d/.go-version"
  : > "$d/triage.tsv"
  : > "$d/pins.tsv"
}
pin() {
  mkdir -p "$d/cases/$1"
  printf '%s' "$2" > "$d/cases/$1/module.mod"
  printf '%s' "$3" > "$d/cases/$1/module.json"
  printf '%s\tex.com/%s\tv1.0.0\th1:x\t-\tMIT\n' "$1" "$1" >> "$d/pins.tsv"
}
expect() {
  want=$1 needle=$2
  shift 2
  got=0
  lake --dir eval/diff exe mitos-diff "$d" "$@" > "$tmp/out" 2> "$tmp/err" || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $needle: exit $got, wanted $want" >&2
    cat "$tmp/out" "$tmp/err" >&2
    exit 1
  fi
  if ! grep -qF -- "$needle" "$tmp/out" "$tmp/err"; then
    echo "FAIL: no '$needle' in the output" >&2
    cat "$tmp/out" "$tmp/err" >&2
    exit 1
  fi
  echo "ok: exit $want, $needle"
}

fresh; pin ok "$okmod" "$okjson"
expect 0 "Stale triage lines: none."

fresh; pin quoted "$quotedmod" "$quotedjson"
expect 1 "$(printf 'quoted\tonly-in-go\trequire\texample.com/q\t#?')"

printf 'quoted\tonly-in-go\trequire\texample.com/q\t#7\n' > "$d/triage.tsv"
expect 0 "(#7)"

fresh; pin ok "$okmod" "$okjson"
printf 'ok\tonly-in-go\trequire\texample.com/gone\t#7\n' > "$d/triage.tsv"
expect 1 "Stale triage lines, which match no mismatch"

fresh; pin pair "$pairmod" "$swappedjson"
expect 1 "require: shared paths in another order"

fresh; pin ok "$okmod" "$okjson"; rm "$d/cases/ok/module.json"
expect 2 "module.json"

fresh; pin ok "$okmod" "$okjson"
printf 'ok\tsideways\trequire\tx\t#1\n' > "$d/triage.tsv"
expect 2 "triage.tsv:1"

fresh; pin ok "$okmod" "$okjson"; mkdir "$d/cases/stray"
expect 2 "cases/ holds"

mkdir -p "$tmp/bin"
cat > "$tmp/bin/go" <<'GO'
#!/usr/bin/env bash
if [ "$1 $2" = "env GOVERSION" ]; then echo "${FAKE_GO_VERSION:-go1.24.7}"; exit 0; fi
if grep -q reject-me "$4"; then echo "go: errors parsing $4: unknown block type: ignore" >&2; exit 1; fi
printf '%s' "$FAKE_GO_JSON"
GO
chmod +x "$tmp/bin/go"
export FAKE_GO_JSON="$okjson"

fresh; pin ok "$okmod" '{}'
PATH="$tmp/bin:$PATH" FAKE_GO_VERSION=go1.25.0 expect 2 "--refresh needs go1.24.7" --refresh
[ "$(cat "$d/cases/ok/module.json")" = '{}' ] || { echo "FAIL: --refresh wrote with the wrong Go" >&2; exit 1; }

fresh; pin ok "$okmod" '{}'; pin bad $'module example.com/bad\nreject-me\n' '{}'
PATH="$tmp/bin:$PATH" expect 2 "bad: go1.24.7 rejects ex.com/bad@v1.0.0" --refresh

fresh; pin ok "$okmod" '{}'
PATH="$tmp/bin:$PATH" expect 0 "Stale triage lines: none." --refresh
[ "$(cat "$d/cases/ok/module.json")" = "$okjson" ] || { echo "FAIL: --refresh did not write Go's bytes" >&2; exit 1; }

cp "$here/check-pins.sh" "$tmp/check-pins.sh"
mkdir -p "$tmp/cases"
cp -r "$here/cases/cobra" "$tmp/cases/cobra"
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" > "$tmp/pins.tsv"
awk -F'\t' '$1 == "cobra"' "$here/licences.tsv" > "$tmp/licences.tsv"
"$tmp/check-pins.sh" > /dev/null
echo "ok: check-pins.sh accepts a pin as committed"
printf '\n' >> "$tmp/cases/cobra/module.mod"
if "$tmp/check-pins.sh" 2> "$tmp/err"; then echo "FAIL: check-pins.sh accepted a changed module.mod" >&2; exit 1; fi
grep -qF "module.mod hashes to" "$tmp/err"
echo "ok: check-pins.sh refuses a changed module.mod"
cp "$here/cases/cobra/module.mod" "$tmp/cases/cobra/module.mod"
sed -i 's/\tApache-2.0$/\tGPL-3.0/' "$tmp/pins.tsv"
if "$tmp/check-pins.sh" 2> "$tmp/err"; then echo "FAIL: check-pins.sh accepted GPL-3.0" >&2; exit 1; fi
grep -qF "licence GPL-3.0" "$tmp/err"
echo "ok: check-pins.sh refuses a licence outside the four"
rm "$tmp/pins.tsv"
got=0
"$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
[ "$got" = 2 ] || { echo "FAIL: check-pins.sh exited $got for a missing pins.tsv, wanted 2" >&2; exit 1; }
grep -qF "cannot read pins.tsv" "$tmp/err"
echo "ok: check-pins.sh refuses a missing pins.tsv"
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" | sed 's/\tApache-2.0$/\tGPL-3.0/' | tr -d '\n' > "$tmp/pins.tsv"
got=0
"$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
[ "$got" = 1 ] || { echo "FAIL: check-pins.sh exited $got for a last row with no newline, wanted 1" >&2; exit 1; }
grep -qF "licence GPL-3.0" "$tmp/err"
echo "ok: check-pins.sh checks a last row with no newline"

mixedjson='{"Module":{"Path":"example.com/app"},"Require":[{"Path":"example.com/b","Version":"v1.0.0"},{"Path":"example.com/a","Version":"v1.0.0"},{"Path":"example.com/c","Version":"v1.0.0"}],"Exclude":null,"Replace":null,"Retract":null,"Tool":null}'
fresh; pin mixed "$pairmod" "$mixedjson"
expect 1 "require: shared paths in another order"
grep -qF "require \`example.com/c\`: only in Go" "$tmp/out"
printf 'mixed\tonly-in-go\trequire\texample.com/c\t#7\n' > "$d/triage.tsv"
expect 1 "$(printf 'mixed\torder\trequire\t-\t#?')"
printf 'mixed\torder\trequire\t-\t#8\n' >> "$d/triage.tsv"
expect 0 "Stale triage lines: none."

pinexpect() {
  local want=$1 needle=$2 got=0
  "$tmp/check-pins.sh" 2> "$tmp/err" || got=$?
  [ "$got" = "$want" ] || { echo "FAIL: $needle: exit $got, wanted $want" >&2; exit 1; }
  grep -qF "$needle" "$tmp/err"
  echo "ok: exit $want, $needle"
}
awk -F'\t' '$1 == "cobra"' "$here/pins.tsv" > "$tmp/pins.tsv"
printf 'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n' > "$tmp/cases/cobra/LICENSE"
pinexpect 1 "LICENSE differs from reviewed source"
sed -i 's/\tApache-2.0$/\tMIT/' "$tmp/pins.tsv"
pinexpect 1 "pin does not match reviewed licence metadata"
cp -r "$here/cases/grpc" "$tmp/cases/grpc"
awk -F'\t' '$1 == "grpc"' "$here/pins.tsv" > "$tmp/pins.tsv"
awk -F'\t' '$1 == "grpc"' "$here/licences.tsv" > "$tmp/licences.tsv"
rm "$tmp/cases/grpc/NOTICE"
pinexpect 1 "no NOTICE"
printf 'changed notice\n' > "$tmp/cases/grpc/NOTICE"
pinexpect 1 "NOTICE differs from reviewed source"
: > "$tmp/pins.tsv"
pinexpect 2 "pins.tsv has no pins"
printf '# header only\n' > "$tmp/pins.tsv"
pinexpect 2 "pins.tsv has no pins"
awk -F'\t' '$1 == "grpc"' "$here/pins.tsv" > "$tmp/pins.tsv"
cat "$tmp/licences.tsv" >> "$tmp/licences.tsv.copy"
cat "$tmp/licences.tsv.copy" >> "$tmp/licences.tsv"
pinexpect 2 "malformed or duplicate licence row"
: > "$tmp/licences.tsv"
pinexpect 1 "no reviewed licence row"
awk -F'\t' '$1 == "grpc" || $1 == "cobra"' "$here/licences.tsv" > "$tmp/licences.tsv"
cp "$here/cases/grpc/NOTICE" "$tmp/cases/grpc/NOTICE"
pinexpect 1 "reviewed licence row has no pin"
```

statements: every proof is in the files above and closes on v4.35.0. What each says:
- `Diff.compareList_eq_nil`, `Diff.compare_eq_nil`: no mismatch exactly when both sides list the
  same paths, in the same order, the same number of times. This is what exit criterion 4's "no
  mismatch" means, and it is the one check of order and count against Go. The gate checks neither
  (#282); `GoMod.run_eq` ties them to the model.
- `Diff.Keys.ofPlugin_eq_model`: the plugin's keys are the model's keys, by `GoMod.run_eq`. So a
  mismatch is a difference between the reviewed model and Go, not a plugin bug, and P2-007's
  deferral ("cite `GoMod.run_eq`") is met.
- `Diff.readingsFrom_offsets`, `Diff.readings_offsets`: `Models.GoMod.readings` has one element
  per line of `Mitos.lines`, at the same byte offset. So `unreadLines`, which zips the two, pairs
  each line with its own reading. P2-006's Usage says this in prose; here it is a statement.
- `Diff.Finding.ofFields_fields`: a finding printed as a triage line reads back as itself. The
  line the report prints for an untriaged mismatch can be pasted into `triage.tsv` as it is.
- `Diff.verdict_clean`: the run is clean (exit 0) exactly when every finding has a triage line and
  every triage line matches a finding.
- Kernel fixtures, run by Lean's kernel at each build (about 4 s): `Diff.ofPlugin_wholeFile`, the
  keys of P2-006's golden `wholeFile`, and `Diff.unreadLines_wholeFile`, its unread lines with
  their 1-based numbers, `(3, "go 1.22")` and `(11, "replace example.com/lib => ../lib")`.
- Axioms, from `#print axioms` in a scratch file: `compareList_eq_nil`, `compare_eq_nil`,
  `readingsFrom_offsets` and `Finding.ofFields_fields` use `propext` only; the other five use
  `propext`, `Classical.choice` and `Quot.sound`. No `sorry`.
- Helpers a builder may reshape, keeping every statement above as written: `unmatched`,
  `compareList`, `Keys.ofFacts`, `Triage.issuesFor`, `findings`, `render`, `Mismatch.describe`,
  `refresh`.

reuse:
- `GoMod.extractor` and `GoMod.run_eq` (`examples/acme/Plugins/GoMod.lean`).
- `Models.GoMod.readings`, `readingsFrom`, `Mode.step`, `Reading.unread`, `facts` and the golden
  `wholeFile` (`examples/acme/Models/GoMod.lean`, `examples/acme/Models/GoMod/Examples.lean`).
- `Mitos.lines` (`core/Mitos/Core/Lines.lean`).
- `Lean.Json`: `Json.parse`, `getObjVal?`, `getObjValAs?`, `getObjValD`, `getArr?`.
- The layout of `eval/score` (lakefile, `Main.lean` with a directory argument and a usage string,
  `parseLabels`, `Scorecard.render`), `warningAsError` from `eval/mutants/lakefile.toml`, and
  `eval/fixtures/toy/.gitattributes`.
- Lemmas: `List.append_eq_nil_iff`, `List.map_eq_nil_iff`, `List.filter_eq_nil_iff`,
  `List.map_cons`, `ite_false`.

fixtures:
- F0, the run on the 13 pins (Usage). 2,067 Go facts and 2,065 plugin facts; 2 mismatches, both
  rsc-quote's quoted paths, both triaged; 109 lines outside the subset: `go`, `toolchain`,
  `godebug`, `replace` lines and blocks, `exclude`, `retract` with a bracketed interval and in a
  block, `tool` in a block, and two quoted paths. The pins hold no `exclude (` or `godebug (`
  block and no `tool` line, but the model reads every block verb on one path (`Mode.step`), so
  they add no case. argo-cd line 44, a comment holding a `"`, is read as blank. The vendoring
  commands (types) reproduced all 28 committed `module.mod`, `LICENSE` and `NOTICE` files byte
  for byte.
- Kernel fixtures `Diff.ofPlugin_wholeFile` and `Diff.unreadLines_wholeFile` (statements).
- Guards, `#guard`, run by every build. The two in `Plugin.lean` run the compiled plugin.

| Guard | File | What it says |
|---|---|---|
| `laxBlockOpener` | `Plugin.lean` | the model reads `require a (` as requiring `a` (F3): modules `example.com/app`, requires `a` and `c/d` |
| a file with no `module` line | `Plugin.lean` | no module key, one require key |
| eight `compare` cases | `Compare.lean` | equal lists give no mismatch; a rotation gives `order`; a path Go lists twice is `onlyIn go`; an empty module list against `,` is `onlyIn go module`; a swapped pair is `onlyIn go` for Go's path, then `onlyIn plugin` for the plugin's; shared order is independent of both membership differences; an excess duplicate preserves first shared occurrences |
| `Module.Path` of `""` and `Require: null` | `Go.lean` | both read as empty lists (Go prints these for a file with no `module` or no `require`) |
| a `Require` entry with an `Indirect` field | `Go.lean` | only the paths are read |
| a JSON with no `Module`, and one whose `Require` is a number | `Go.lean` | `Keys.ofGoJson` fails, so the run exits 2 |

- T1 to T28, `eval/diff/selftest.sh`, one script with no Go and no network. It builds throwaway
  case folders whose go.mod and Go output are fixed text (the outputs are `go mod edit -json` of
  Go 1.24.7, compacted; F4), and for `--refresh` puts a stand-in `go` first on `PATH` that prints
  a version, rejects a file that says `reject-me`, or prints the output it is given. It runs from
  any directory. Measured, one run, 3.8 s:

| # | Input | Exit | What it shows |
|---|---|---|---|
| T1 | one pin, no triage | 0 | the clean run |
| T2 | a quoted path Go has and the plugin lacks, no triage | 1 | the line to add is printed, ending in `#?` |
| T3 | the same, with its triage line | 0 | `(#7)` is printed beside the mismatch |
| T4 | a triage line that matches nothing | 1 | "Stale triage lines, which match no mismatch" |
| T5 | Go's requires in the other order | 1 | `require: shared paths in another order` |
| T6 | a pin with no `module.json` | 2 | the IO error names the file |
| T7 | a triage line with an unknown mismatch word | 2 | `triage.tsv:1` |
| T8 | a case directory `pins.tsv` does not list | 2 | `cases/ holds [...], pins.tsv lists [...]` |
| T9 | `--refresh` with a Go that says go1.25.0 | 2 | `--refresh needs go1.24.7`, and no file written |
| T10 | `--refresh` with a Go that rejects one file | 2 | `bad: go1.24.7 rejects ex.com/bad@v1.0.0: ...` |
| T11 | `--refresh` with a Go that accepts | 0 | `module.json` holds the stand-in's bytes |
| T12 | `check-pins.sh` on cobra's committed row | 0 | the clean pin |
| T13 | the same, one byte appended to `module.mod` | 1 | `module.mod hashes to h1:...` |
| T14 | the same, the licence column set to `GPL-3.0` | 1 | `licence GPL-3.0 is not one of the four` |
| T15 | the same, `pins.tsv` removed | 2 | `cannot read pins.tsv`, and the exit status is exactly 2 |
| T16 | the same, a one-row `pins.tsv` with no final newline and the licence `GPL-3.0` | 1 | `licence GPL-3.0`: the last row is checked, and the exit status is exactly 1 |
| T17 | plugin `[a,b]`, Go `[b,a,c]` | 1 | both `only in Go c` and `shared paths in another order` |
| T18 | T17 with only the membership finding triaged | 1 | the order finding remains untriaged |
| T19 | T18 with the order finding triaged too | 0 | no stale or untriaged findings |
| T20 | correct cobra pin/metadata, LICENSE replaced with GPL text | 1 | `LICENSE differs from reviewed source` |
| T21 | T20 with `pins.tsv` claiming MIT | 1 | `pin does not match reviewed licence metadata` |
| T22 | correct grpc pin, required NOTICE removed | 1 | `no NOTICE` |
| T23 | the same, NOTICE changed | 1 | `NOTICE differs from reviewed source` |
| T24 | empty `pins.tsv` | 2 | `pins.tsv has no pins` |
| T25 | header-only `pins.tsv` | 2 | `pins.tsv has no pins` |
| T26 | duplicate licence manifest row | 2 | `malformed or duplicate licence row` |
| T27 | pin with no licence manifest row | 1 | `no reviewed licence row` |
| T28 | licence manifest row with no pin | 1 | `reviewed licence row has no pin` |

- F1, `--refresh` with Go 1.24.7 on `PATH`: exit 0 in 0.6 s, every `module.json` byte the same
  (`diff -r` of `cases` before and after is empty), the 13 files together hash to `45b45018c442…`
  (`cd eval/diff/cases && find . -name module.json | LC_ALL=C sort | xargs cat | sha256sum`). Two
  refreshes in a row gave the same bytes.
- F2, the comparison with no Go on `PATH` (an `env PATH=...` that holds `lake` and not `go`, where
  `command -v go` printed nothing): exit 0, the same bytes as F0.
- F3, the lax case, three readers on one file, measured with Go 1.24.7's `modfile.Parse` (the
  `go mod edit -json` run) and `modfile.ParseLax` (the sonnet runner's scratch program on the
  `x/mod` that `$GOROOT/src/cmd/vendor` holds, rerun by the judge) and with this plugin. The file is
  `module example.com/app`, `require a (`, `\tb v1.0.0`, `)`, `require c/d v1.0.0`:

| Reader | Module | Requires |
|---|---|---|
| strict `modfile.Parse` (`go mod edit -json`) | none: `unknown block type: require a` | none |
| lax `modfile.ParseLax` | `example.com/app` | `c/d` (the block is ignored) |
| `GoMod.extractor` | `example.com/app` | `a`, `c/d` |

  Two other cases, so nobody derives them again: an unknown directive (`foo bar baz`) is rejected
  by strict and ignored by lax, and the model reads it as unread, so it agrees with lax; a quoted
  path (`require "example.com/q" v1.2.0`) and `module ,` are read by both Go parsers and skipped
  by the model, which is the plan's subset, and is what `triage.tsv` is for.
- F4, the Go outputs behind T1 to T11 and F3: Go 1.24.7 accepts `module ,` (Path `,`), a quoted
  require path (Path without the quotes), and a file with no `module` line (`"Path": ""`); it
  rejects a second `module` line (`repeated module statement`) and `require a (` (above). With no
  `go` line it prints no `Go` field. Its JSON lists `Require` in file order, also for an unsorted
  block (`z`, `a`, then `m`, `b`).
- F5, wrong code, measured in a scratch copy. It shows what stops each one.

| # | Wrong code | What stops it |
|---|---|---|
| M1 | `compareList` without the order check (multisets only) | `compare_eq_nil` has no proof, and the reorder guard fails |
| M2 | `unreadLines` numbering from 0 | the kernel fixture `unreadLines_wholeFile` |
| M3 | `verdict` that never reports a stale line | `verdict_clean` has no proof |
| M4 | an empty Go module path counted as a key | the `Go.lean` guard |
| M5 | `Keys.ofPlugin` reading `Models.GoMod.facts` | `Keys.ofPlugin_eq_model`: its `rw [GoMod.run_eq]` finds nothing to rewrite |
| M6 | the `require` lists not compared | `compare_eq_nil` and the guards |
| W1 | the plugin's fold without its final `reverse`, `run_eq` kept | the plugin does not build (`run_eq` has no proof) |
| W2 | the same, with `run_eq` dropped and the obligations proved by `sorry` | this build: `Unknown identifier GoMod.run_eq` in `Keys.ofPlugin_eq_model` |
| W3 | the same, with `Keys.ofPlugin_eq_model`, `ofPlugin_wholeFile` and the two plugin guards dropped too | the run: exit 1, an `order` mismatch in each of the 12 modules other than rsc-quote |

- Not pinned by a fixture: a lone punctuation path (`module ,`). The model reads that line as
  unread, and Go prints the path `,`. No pinned module has one (P2-006, owner decision O4). The
  `compare` guard shows how it would print.

### Checks, in order

From the repository root, at the head after the last rebase.

1. S1 prints nothing.
2. `lake --dir eval/diff build` prints `Build completed successfully`. With `warningAsError`, a
   warning fails it. `grep -rn 'sorry\|FactKind' eval/diff/Diff eval/diff/Main.lean` prints
   nothing.
3. `cmp lean-toolchain eval/diff/lean-toolchain` prints nothing.
4. A scratch file with `import Diff.Report` and `#print axioms` for each of the nine statements
   prints only `propext`, `Classical.choice` and `Quot.sound` (statements). Run it with
   `cd eval/diff && lake env lean <scratch>/Axioms.lean`.
5. `eval/diff/check-pins.sh --online` prints nothing and exits 0. It needs `curl`, `openssl` and the
   network, not Go. Without `--online` it needs neither network nor `curl`.
6. `eval/diff/selftest.sh` prints twenty-eight `ok:` lines and exits 0.
7. With Go 1.24.7 on `PATH` (`go version` prints `go1.24.7`),
   `lake --dir eval/diff exe mitos-diff eval/diff --refresh` exits 0, and then
   `git status --porcelain eval/diff` prints nothing. Measured: the 13 files hash to
   `45b45018c442…` (F1).
8. With no `go` on `PATH`, `lake --dir eval/diff exe mitos-diff eval/diff` exits 0 and prints the
   report of Usage (F2).
9. `git diff --name-only origin/main...HEAD` prints only paths under `eval/diff/`,
   `tasks/P2-008-gomod-diff.md` and `ops/runs/`.
10. `lake exe mitos-gate runlog --head ops/runs`, and
    `git diff --name-status --no-renames origin/main...HEAD -- ops/runs ':!ops/runs/README.md'`
    shows only `A` lines.
11. `.claude/scripts/plan-tasks.test.sh`, because this file changes. With this file in `tasks/` and
    `P2-008` removed from `.claude/scripts/plan-tasks.pending` it prints
    `ok   the tree: every linked row has a design or is pending` (measured in a scratch tree). The
    PR that lands this design makes the `.claude/` edit; the builder's PR does not touch `.claude/`.
12. The verifier, in its own worktree: checks 1 to 8 again; opens each issue number in
    `eval/diff/triage.tsv` and finds the quoted-path issue open with the `follow-up` label;
    compares one pin's `module.json` with `go mod edit -json eval/diff/cases/<case>/module.mod`;
    and runs two mutants of F5 (M1 and M3, one edit each) and sees the named failures.
13. In CI, `gate` is green. No CI step builds `eval/diff`. `.github/scripts/install-toolchains.sh`
    reads every `lean-toolchain` and installs each distinct one, so the new file adds no toolchain
    while it matches the root's.

### Risks and stop conditions

Risks:
- R1. Nothing in CI builds `eval/diff` until P2-012. A PR that renames a model or plugin name it
  uses, or drops `GoMod.run_eq`, merges green and breaks this build on `main`. The nightly run of
  P2-012 is the first automatic check. Until then, a builder of a PR that touches
  `examples/acme/Plugins/GoMod.lean` or `examples/acme/Models/GoMod*` can run check 2 by hand.
- R2. Go 1.24.7 is past upstream support (1.26 and 1.27 are supported), and its strict parser
  rejects the `ignore` directive of Go 1.25 (gitea v1.27.3, lazygit). A pin is chosen among files
  it accepts. A Go bump is one PR: `.go-version`, `--refresh`, and the diff of the 13
  `module.json` files is its review.
- R3. Adding a pin and `check-pins.sh --online` need `proxy.golang.org`, `sum.golang.org` and
  `raw.githubusercontent.com`. The run, the refresh and the offline pin check need no network.
- R4. A licence or NOTICE file outside the repository root is not fetched. Of the 13, only grpc
  (`NOTICE.txt`) and prometheus (`NOTICE`) have a root NOTICE, and both are vendored as `NOTICE`.
- R5. A toolchain bump can break a `simp` route here; the routes name five lemmas (reuse), and
  `warningAsError` turns a deprecation into an error (P2-011 deferral).
- R6. The vendored data is about 400 KB of text.
- R7. Bot noise. CodeRabbit may comment on the 41 vendored files (a go.mod that pins an old
  dependency, a licence text). `.coderabbit.yaml` has no path filter for them and is outside this
  row's cells (deferrals). The PR body says the files are vendored and pinned; an answer such as
  "vendored, hashed by `check-pins.sh`" is enough, and a security-flavoured finding gets its thread
  left open for the owner.
- R8. `check-pins.sh` hashes with `openssl`. It is on `ubuntu-24.04` runners and on the design
  machine. A runner without it exits 2 with a message, never green.

Stop conditions for the builder:
- S1. Before writing, after `git fetch origin main`, this prints nothing:

```
git diff --stat 85981fe origin/main -- examples/acme core/Mitos lean-toolchain eval/score/lean-toolchain tasks/P2-011-toolchain-readiness.md
```

  If it prints a file, build the sketch first. If it builds and F0's numbers hold, go on and say so
  in the PR body. Otherwise stop: this design is amended first. A change in `core/Mitos/Core/Fact.lean`
  or `Lines.lean`, or in `examples/acme/Models`, is the one that matters.
- S2. Before writing `triage.tsv`, file one issue, labelled `follow-up`, for the model's quoted
  paths, unless one exists by then: "go.mod model: a quoted path gives no fact". It names the
  rsc-quote findings, P2-006's evidence (14 of 850 go.mod texts that Go accepts hold one) and that
  the fix is a model change, so `spec-approved`. Issue #328 already holds this finding with the
  `follow-up` label. The two triage lines cite it. The report lists the issue's id.
- S3. A pin's licence is not one of Apache-2.0, BSD-2-Clause, BSD-3-Clause and MIT, or the
  licence file is missing, differs from its reviewed source bytes, or a required NOTICE differs: stop, and the root asks the owner (plan, class C). None of the 13.
- S4. Check 5 prints a line, or Go 1.24.7 rejects a pin: drop or replace that pin, never the check.
  Report the change. A hash that differs from `pins.tsv` means the version was re-tagged: stop and
  report which pin.
- S5. A mismatch other than rsc-quote's two appears. Do not edit the plugin, the model, a pin or
  `triage.tsv` to get green. If it is `only-in-go` or `order`, file or find the model issue,
  triage it and report it. If it is `only-in-plugin`, the model gives a fact Go lacks on a file Go
  accepts, which P2-006's evidence never saw: stop and report the file.
- S6. A statement or a guard does not hold as written. The builder may reshape a helper (the list
  under statements), never a statement and never `Keys.ofPlugin_eq_model`, which it neither
  weakens nor drops. A route that stops closing after a toolchain move goes to a PR owner on opus
  at xhigh.
- S7. The builder stops when the PR is open on `main`, `gate` is green, checks 1 to 11 pass at the
  head and every thread is answered, and reports that head as merge-ready. No path here is the
  owner's, so an agent merges it.

cut_line: ships `eval/diff`: the runner, its statements and guards, 13 pins with their outputs and
licences, the two scripts and the triage of the 2 quoted-path findings. It leaves the nightly
refresh, a CI build of `eval/diff` and the `docs/process.md` row to P2-012, a lax-parser run and a
Go bump to deferrals.

deferrals:
- To P2-012 (#213): the nightly job of Usage (setup-go from `.go-version`, `check-pins.sh`,
  `--refresh`, `git diff --exit-code eval/diff/cases`, the report posted), and a CI build,
  `lake --dir eval/diff build` and `eval/diff/selftest.sh`, on PRs that touch `eval/diff/`,
  `examples/acme/Plugins/GoMod.lean` or `examples/acme/Models/GoMod*`, which closes R1. The run
  takes 0.3 s and needs no Go, so P2-012 may also run it on those PRs; it stays evaluation, not a
  gate. Whether the nightly fails on exit 2 is that PR's call. The "Differential tests against real
  tools" row of `docs/process.md` ("What runs where") still says "Phase 2" where a command goes; it
  gets `lake --dir eval/diff exe mitos-diff eval/diff` and `eval/diff/check-pins.sh`. Both paths
  are the owner's.
- To P2-011 (#147), PR B: it already writes `eval/diff/lean-toolchain`. Its step 8 also runs
  `lake --dir eval/diff build && lake --dir eval/diff exe mitos-diff eval/diff` and
  `eval/diff/selftest.sh`, and its touches add `eval/diff/Diff/` and `eval/diff/lake-manifest.json`
  in case a route breaks. Its `revisit_when` ("after #209 merges") is when that file is amended.
  This row does not touch it.
- To the quoted-path issue of S2: the two rsc-quote findings. It is also P2-006's deferral "Quoted
  paths", which #328 now holds.
  Also to a model issue, no row, which the first agent that needs a triage row files: `module ,`
  and other lone punctuation paths (P2-006 O4), and `// indirect` as a flag (P2-006's deferrals).
  Changing any of them is a model PR with `spec-approved`, and then the guards of this row are
  updated.
- To #209 and #275 item 3: the lax parser. The run compares against strict only, and says so. A
  lax run would need Go code calling `golang.org/x/mod/modfile.ParseLax`, which this repository has
  none of; the one fact-changing lax case is listed above and pinned by the `laxBlockOpener`
  guard. Reopen it if a real pin ever shows a lax-only difference.
- To #282 and #292 item 1: nothing changes there. This run is the one outside check of order and
  count, and it holds only while `GoMod.run_eq` does (`Keys.ofPlugin_eq_model`, F5 W1 to W3).
  Whether acceptance itself should pin them is the owner's call.
- To P2-009b (#211): it may copy any pinned `module.mod` as a fixture's `go.mod`, as its own copy
  (plan, Shared files 5), with its own `.gitattributes`. It shares no path with this row.
- To `.coderabbit.yaml`, a root file outside this row's cells (R7): a path filter
  `!eval/diff/cases/**`. The root decides who edits it.
- To a follow-up issue, no row: bump `.go-version` to a supported Go (R2). Then gitea v1.27.3 can
  be pinned, and its `ignore (` block is read as unread lines.
- To a later row, if the report grows unwieldy: group the unread lines by directive and print a few
  of each. This row lists every line, as the plan says.
- From P2-006: a file Go rejects is reported by `--refresh` (exit 2, T10) and never vendored, so it
  is never a mismatch. A quoted path is an unread line (F0, rsc-quote). A lone punctuation path
  would be one too (fixtures, "Not pinned").
- From P2-007: `Keys.ofPlugin_eq_model` cites `GoMod.run_eq`.
- From #160 item 2: the pins, the Go version and the licences are named here and in `pins.tsv`,
  and `check-pins.sh` checks the SPDX allowlist, pin-to-licence metadata and reviewed LICENSE/NOTICE bytes.
- From #285 item 6: no `match` on `FactKind` (check 2 greps for the name).

owner_decisions:
- Settled by the plan: the outputs are vendored and the comparison needs no Go; the nightly refresh
  and the CI wiring are P2-012's; the run is evaluation, not a gate; `eval/diff` is its own Lake
  project with its own `lean-toolchain`; an agent merges it (class A). Class C, an unclear licence,
  applies to none of the 13 pins.
- This design's defaults, not owner rulings. The root states them in #209's body when it hands the
  row over, as it did for #208, and an owner answer there replaces a default:
  - O1. Licences. Keep a go.mod and Go's output of it with the repository's licence file beside
    them (and its root NOTICE), for modules under Apache-2.0, BSD-2-Clause, BSD-3-Clause and MIT
    only (`check-pins.sh`'s allowlist and reviewed `licences.tsv` source hashes). Each licence's notice condition then holds for the copied
    file. A go.mod is a list of module paths and versions, which may not be a copyrightable work
    at all; the licence file is kept so that no reading of the licences needs that argument. Cost:
    81 KB.
  - O2. The strict parser, because each pin is its module's own go.mod (The parser this run
    compares against).
  - O3. Go 1.24.7, because P2-006's rule table, P2-006's and P2-007's runs and this design's are
    all against it, and it is the Go of the development container. Cost: R2.
  - O4. Pins by module version from the module proxy, each with its go.sum hash, which
    sum.golang.org's transparency log confirms. A commit pin on GitHub has no such log, and the
    GitHub API refused the design sessions for other repositories.
  - O5. rsc.io/quote v1.5.2 pinned on purpose, a real module whose two quoted paths keep the
    triage path running every night.
  - O6. A stale triage line fails the run, so the file shrinks when the model learns a rule.
  - O7. A pin Go rejects fails the refresh (exit 2) and is never vendored, so a skipped pin cannot
    hide in a green nightly.
  - O8. `warningAsError` in this project, and the vendored names `module.mod` and `module.json`.

## Rationale

### Problem

The row compares the plugin with the real tool on real files, and the comparison must run with no
Go. Five things shape it. The gate's obligations are about membership (#282), so this run is where
order and count meet Go, and it must lean on `GoMod.run_eq`. Go has two go.mod parsers (#209), so
the run names one. Its exit status is what P2-012's nightly and exit criterion 4 read, so "no
untriaged mismatch" needs a precise meaning. Pinned third-party files need clear licences (#160).
And nothing in CI builds this project until P2-012, so its own build has to carry its checks.

### Shape

- Data first. `Keys` is what one go.mod says in Go's terms: the `module` paths and the `require`
  paths, each in file order. Both sides are parsed into it at the boundary: Go's JSON in
  `Diff.Go`, the plugin's facts in `Diff.Plugin`. Nothing after that sees JSON or `Fact`.
- `compare` returns the mismatches of two `Keys` as lists, repeats counted, and an `order`
  mismatch when shared paths come in another order, even when membership also differs. `compare_eq_nil` states what an empty answer
  means. `verdict_clean` states what exit 0 means. The rest of the report is presentation.
- The plugin side cites `GoMod.run_eq`, so this build is a second guard on #282's gap, and a
  mismatch speaks about the model. If someone drops the citation too, the run itself shows the
  order (W3).
- The unread lines come from the model's own walk, `Models.GoMod.readings`, zipped with
  `Mitos.lines`; `readings_offsets` states that the zip pairs each line with its reading. No second
  tokenizer and no second walk.
- Each file format has one owner: `pins.tsv` in `Diff.Pins`, `triage.tsv` in `Diff.Triage` (with
  its round trip), Go's JSON and Go's process in `Diff.Go`, the directory layout in `Main`. Two
  lists that could drift are checked against each other at every run: the case directories against
  `pins.tsv` (exit 2), and `triage.tsv` against the findings (exit 1). The bytes are checked by
  `check-pins.sh`, which reads the same six columns as `parsePins`; a changed column count breaks
  both loudly.
- Idempotence. The run only reads. `--refresh` gives the same bytes when run twice (F1), and one
  that stops halfway leaves some outputs new and some old, which `git diff` shows and a second
  refresh repairs.
- Interface. The caller sees one command with one flag and three exit codes, four plain files and
  two scripts. Behind it sit the JSON format, the empty-module-path rule, the strict parser, Go's
  environment, the multiset and order comparison, the alignment of lines and readings, and the
  triage matching. Per boundary-discipline the wire types stop in `Diff.Go`; per
  encode-lessons-in-structure the rules that matter are statements, guards or selftest cases, not
  prose.

### Synthesis decision

The runners were an opus one (A) and a sonnet one (B), the judge a sonnet one; the owner ruled
`fable` out for its token cost. Both candidates built and ran on `main` at `68e37a9`. The judge
rebuilt the synthesis on `main` at `85981fe`, read both files end to end, scored them on five
criteria (the statements say what exit 0 means; the plugin side is tied to `run_eq`; the lines
outside the subset are listed from the model's own walk; the data and the Go process are safe to
vendor and refresh; a verifier can re-run every claim with no Go), and checked both against
`main`, #209, #282 and the P2-006, P2-007 and P2-011 task files.

- The base is A. Reasons, by criterion:
  - Statements. A's `compare_eq_nil` and `verdict_clean` are equivalences, and one `Mismatch` type
    carries order, count and side. B's `Report.of_ok` goes one way (ok implies covered), and its
    `Delta` needs three count lemmas that a toolchain bump can break.
  - Lines outside the subset. A zips the model's `readings` with `Mitos.lines` and proves the zip
    aligned in about 24 lines (`UnreadLine`, the two offsets statements, `unreadLines`). B's
    `Unread.lean` is 69 lines: it walks `Mode.step` again (`walkFrom` and a proof that it equals
    `readingsFrom`) to label block lines, then groups them and prints three samples a group; the
    plan says the lines are listed.
  - Safety of the data and the Go call. A names the vendored files `module.mod`, so GitHub's
    dependency graph and Go's module discovery ignore them (A8); B's `go.mod` under `pinned/`
    does not. A runs Go from typed code with five settings and a version refusal; B sets one
    variable in shell. A refuses a pin Go rejects (exit 2); B counts it and passes (O5 there),
    which would let a nightly drift to "3 rejected" with nothing compared.
  - Real data. A pins rsc.io/quote, so the triage path runs on a real mismatch every night and
    exit criterion 4 is met by something, and S2 closes P2-006's missing issue. B's real data never
    differs, so its exit 0 is vacuous and the triage path is exercised by selftest only.
  - Coverage. A's 13 pins cover `retract` in a block and on a line, `tool` in a block and
    `replace` lines and blocks, beside what B's 11 cover; the model reads every block verb on one
    path, so B's `exclude (` and `godebug (` blocks add no case.
- Grafted from B:
  - The lax opener as a build-checked guard on the compiled plugin (A had it as a measurement),
    with B's three-reader table, rerun here against Go 1.24.7's strict and lax parsers.
  - `Keys.ofGoJson` guards (A had F11 as a scratch measurement), and five `compare` guards.
  - A committed `selftest.sh` with no Go, no network and no `jq` (A's F1 to F8 needed Go, `jq` and
    a download, and lived in the task file); the stand-in `go` for the `--refresh` plumbing is the
    judge's.
  - A committed `check-pins.sh`: B's offline hash and licence check, with A's sum.golang.org
    cross-check behind `--online`.
  - R7 and the `.coderabbit.yaml` deferral; the reasons for pins left out; the verifier opening
    each issue number in `triage.tsv`; the `FactKind` grep; the O1 licence reasoning; the role
    line.
- Changed by the judge: `runGo` and `refresh` moved from `Main` into `Diff.Go`, so one module owns
  everything about Go; S1 re-based on `85981fe` and widened to the paths both candidates watched.
- Kept from A on purpose: `warningAsError`, so a `sorry` or a deprecation fails the build, which
  nothing in CI would catch before P2-012.
- Rejected from B: `Delta` and its count lemmas; `walkFrom`, grouping and samples; `rejected`
  pins that pass; nested `pinned/<module>@<version>/` folders with a `PIN` file each (a second
  per-pin file with the fields `pins.tsv` holds in one place); `vendor.sh` and `refresh.sh` (the
  Lean `--refresh` shares one Go environment with the run); a lax lane; no `warningAsError`; 11
  pins.
- Convergence: both chose a Lake project with its own `lean-toolchain`, the strict parser named in
  the report and the lax case listed, one `Keys` of two ordered lists at the boundary, a citation
  of `GoMod.run_eq`, proxy pins with their go.sum hashes, Go 1.24.7, a licence allowlist, `* -text`,
  and the same deferrals to P2-011 and P2-012. No dropout.
- Verification: Evidence.

### Tradeoffs accepted

- We accept 400 KB of vendored text, licences included, in exchange for a run that needs no Go and
  no network, and pins whose bytes sum.golang.org confirms.
- We accept an unsupported Go release (R2) in exchange for one Go version across P2-006's rule
  table, P2-007's run and this one. The bump is one reviewed PR.
- We accept a runner that fails on a stale triage line, which costs an edit when the model learns a
  rule, in exchange for a triage file that never hides a fixed finding.
- We accept `module.mod` and `module.json` instead of the upstream name, which reads less
  directly, in exchange for no dependency alerts and no Go module roots inside the repository.
- We accept a `decide +kernel` cost of about 4 s per build for two fixtures that pin the keys and
  the line numbering on a reviewed golden file.
- We accept the strict parser only, in exchange for comparing each file with the parser that reads
  it in its own repository. The lax difference is listed and guarded, not run.
- We accept a report that lists every line outside the subset (109 lines over 13 modules, most of
  them `replace` blocks), in exchange for one walk and no grouping rules.
- We accept two readers of the six `pins.tsv` columns, `parsePins` and `check-pins.sh`, in exchange
  for hashing with the tools that already do it; the selftest runs both on a real row.
- We accept two shell scripts next to the Lean, because they check the bytes and the exit codes that
  Lean only reads.

### Alternatives considered

- A shell runner, `jq` against a `lake env lean --run` dump, as P2-007's F4. It is shorter, but
  "no mismatch", the empty module path and the triage rule then live in shell with no statement,
  and the plan names a Lake project.
- Vendoring `jq`'s projection of Go's output instead of Go's output. The Lean side would need no
  JSON parser, but the vendored file would no longer be what Go printed, and the projection's rules
  would sit in a script.
- A set or multiset comparison, the gate's view. It hides exactly what only `GoMod.run_eq` pins.
- A three-way `Delta` (same, reordered, differ) with count lemmas. It says no more than `order`
  and `compare_eq_nil` do, and it adds lemmas that a toolchain bump can break.
- Re-walking `Mode.step` to label block lines and group them. It buys a shorter report at the price
  of a second walk and a proof that it equals the model's.
- A per-line alignment of Go's entries with source lines. `go mod edit -json` gives no positions,
  so it needs a Go program on `golang.org/x/mod`, and Go code in this repository.
- Commit pins on GitHub with raw URLs. No transparency log confirms the bytes, and these sessions
  cannot call the GitHub API on other repositories.
- A folder per module version with a `PIN` file, the folder list as the pin list. It removes one
  list, but the paths nest to a variable depth, each pin gets a second file, and the drift it
  removes is already a loud exit 2 here.
- Counting a pin Go rejects as `rejected` and passing. A pin that compares nothing is a nightly
  that checks less than it says.
- P2-006's twelve golden files as more cases. They are locked model data already compared with Go
  in P2-006's table, and the row's scope is pinned repositories.

### Open questions and risks

- Should `.go-version` move to a supported Go now, at the cost of re-checking P2-006's rule table
  against it? The default keeps 1.24.7 (owner_decisions, R2).
- Should P2-012 run the comparison and `selftest.sh` on PRs that touch the plugin, the model or
  `eval/diff`? It takes 0.3 s with no Go. The plan calls it nightly evaluation.
- Is a licence file beside a go.mod enough for the Apache-2.0 pins (O1), or does the owner want only
  MIT and BSD pins? The default keeps six Apache-2.0 pins.
- Not verified: `actions/setup-go` reading `eval/diff/.go-version` (A3), Go releases other than
  1.24.7, and GitHub's dependency graph ignoring `module.mod` (A8).

### Assumptions

- A1. `go mod edit -json` prints a function of the file's bytes and the Go release only: two
  refreshes gave the same bytes, and the JSON holds no path or time.
- A2. `proxy.golang.org` serves a module's own go.mod as `<version>.mod`: each of the 13 hashes to
  sum.golang.org's `/go.mod` line (`check-pins.sh --online`).
- A3. `actions/setup-go` accepts `go-version-file: eval/diff/.go-version` (P2-012 relies on it).
- A4. Go 1.24.7 stays downloadable for P2-012's runner.
- A5. The repository's root licence at the version's tag covers the module's go.mod; for gopls,
  a nested module, that is golang/tools' root `LICENSE`.
- A6. The root `.gitignore` line `.lake/` keeps `eval/diff/.lake` out of git.
- A7. CI stays green: no CI step builds `eval/diff`, and the toolchain installer deduplicates.
- A8. GitHub's dependency graph reads files named `go.mod`, not `module.mod`.
- A9. A triage line covers every occurrence of its mismatch, and the comparison is of keys only.

### Where the plan row and `main` disagree

- The Reads cell names only `examples/acme/Plugins/GoMod.lean`. The runner also reads
  `examples/acme/Models/GoMod.lean` (`readings`, `readingsFrom`, `Mode.step`, `facts`),
  `examples/acme/Models/GoMod/Examples.lean` (`wholeFile`) and `core/Mitos/Core/Lines.lean`
  (`Mitos.lines`), as P2-007's deferral already says. "Lines outside the model's subset" needs the
  model. It writes none of them.
- The row says "pinned repos". A pin here is a module version, which names its repository and tag
  in `pins.tsv`. `main` has no list.
- The Owns cell lists "the pinned go.mod files and their vendored outputs". The design adds the
  licences, `pins.tsv`, `licences.tsv`, `triage.tsv`, `.go-version` and two scripts, all under `eval/diff/`.
- P2-006's deferrals said a file Go rejects is "reported as rejected". Here `--refresh` reports it
  and writes nothing, so a rejected file never reaches the comparison.
- P2-006 deferred quoted paths "to a follow-up issue". Issue #328 now holds them, as S2 requires.
- `docs/process.md`, "What runs where", has no command for the differential row, and
  the design PR removed `P2-008` from `.claude/scripts/plan-tasks.pending`. Both are the owner's
  paths (Context, deferrals).
- `tasks/P2-011-toolchain-readiness.md` re-pins `eval/diff/lean-toolchain`, but its step 8 does
  not build `eval/diff` and its touches do not list `eval/diff/Diff/` (deferrals).
- `plan/phase-2.md` says the nightly "refreshes the outputs with Go, then runs the comparison".
  This row ships the refresh and the run; P2-012 wires them.

### Next implementation step

Run S1, confirm the existing issue #328 for S2, fetch the 13 pins and their licences,
write the files under `types`, then run checks 2, 5, 6 and 7.

### Evidence

All measured in a scratch copy of `main` at `85981fe`, Lean v4.35.0, Go 1.24.7, 4 vCPU, one run
each unless said. The runners' own measurements, on `68e37a9`, agreed.
- The type-check: `lake --dir eval/diff build` from the root of the copy, with `core` and
  `examples/acme` built: `Build completed successfully (46 jobs)`, no warning under
  `warningAsError`, 9.3 s from an empty `eval/diff/.lake`, the guards and the two kernel fixtures
  included.
- The statements: nine, standard axioms only (statements). The mutants and wrong plugins of F5 each
  stopped as the table says, one build each.
- The run: F0 as in Usage, exit 0 with the two triage lines and exit 1 with an empty `triage.tsv`
  (the report then prints both lines ending in `#?`). F1, F2 and F3 as listed.
- `eval/diff/check-pins.sh`: exit 0 in 0.3 s; with `--online`, exit 0 in 2.3 s, all 13 hashes equal
  to sum.golang.org's go.mod lines. `shellcheck` clean on both scripts.
- Original sketch: `eval/diff/selftest.sh` printed sixteen `ok:` lines in 3.8 s.
- Review revision: the extracted project builds all 46 jobs without warnings; real Go 1.24.7
  `--refresh` keeps the 13-case report and its two triaged findings; the offline and online pin
  checks pass, including all 15 reviewed source documents. All 28 selftests pass. Restoring the
  old comparator makes T17 fail; mutating `problem` to status 2 is accepted by the old T16 fragment
  and rejected by the exact-status T16; removing byte checks fails T20; removing the nonempty-pin
  check fails T24. Each mutant was restored before the final passing run.
- The vendoring commands of `types`, run in a scratch folder: 28 files, byte for byte the
  committed ones.
- Candidates left out: gitea v1.27.3 and lazygit (Go 1.24.7 rejects their `ignore` block, measured
  here), terraform (Business Source License, read from its LICENSE file), and docker/cli (a
  `+incompatible` version, whose go.mod the proxy makes up, so it is no file of the repository; the
  sonnet runner's finding). A repository under AGPL or GPL would stop at S3.
- Not measured: `actions/setup-go` with `go-version-file` (A3), any Go but 1.24.7, GitHub's
  dependency graph (A8), and CI with these files present (no step reads them).

## Done when
- [x] the quoted-path issue filed (S2), and `triage.tsv` cites it
- [x] `lake --dir eval/diff build` succeeds with `warningAsError`, and `grep -rn 'sorry\|FactKind'
      eval/diff/Diff eval/diff/Main.lean` prints nothing
- [x] the plain run exits 0 with the table of Usage, also with no `go` on `PATH`
- [x] `--refresh` with Go 1.24.7 leaves `git status --porcelain eval/diff` empty
- [x] `eval/diff/check-pins.sh --online` prints nothing, and `eval/diff/selftest.sh` prints twenty-eight
      `ok:` lines
- [x] each pin's `LICENSE` is one of the allowlist; the PR body states O1 and the F0 numbers
- [x] `eval/diff/lean-toolchain` reads `leanprover/lean4:v4.35.0`, as P2-011 expects
- [ ] all `checks` pass locally
- [x] no `sorry`, no new axioms
- [x] run-log record written (ops/runs/)

## Builder evidence

Codex materialized the accepted design on `main` at `2277138`. The preferred sonnet model was
unavailable to the agent tool, so this attempt used the inherited Codex model. S1 printed nothing.
The implementation retains every designed statement, signature, guard, and module boundary.
The header-only pin refusal and exact T16 exit status from #308 are present.

- `lake --dir eval/diff build` completed all 46 jobs without warnings on Lean 4.35.0.
- The 13-case run reports 2,065 plugin facts, 2,067 Go facts, two mismatches triaged to #328, and
  109 lines outside the subset. The run exits 0 with no Go on `PATH` and prints identical bytes.
- Go 1.24.7 refreshed all outputs. A repeat refresh leaves `git status --porcelain eval/diff` empty.
- The offline and online pin checks exit 0 without output. The source grants are Apache-2.0,
  BSD-2-Clause, BSD-3-Clause, and MIT. The copied files retain all licence and notice bytes.
- All 28 selftests pass. The nine statement axiom reports contain only `propext`,
  `Classical.choice`, and `Quot.sound`. The toolchain comparison and forbidden-token check pass.
- `plan-tasks.test.sh` and `gh-api-rest.test.sh` pass.
- The required core checks are blocked by this environment's bubblewrap setup. `lake check` and
  `lake comparator --paranoid` fail before verification with a read-only uid-map error. An
  unsandboxed `lake check` also fails while bubblewrap tries to create `/run/user`. CI must supply
  these checks. No trust code or sandbox setting changed.

The PR leaves the nightly job and CI build wiring to P2-012, as the cut line requires. The owner
will merge this PR after independent verification.
