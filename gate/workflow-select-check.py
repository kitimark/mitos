import pathlib
import subprocess
import sys
import tempfile

BIN = pathlib.Path(sys.argv[1]).resolve()

SOURCE = """jobs:
  first:
    steps:
      - name: Setup
        uses: actions/checkout@v4
      - name: Cleanup logs
        if: always()
        run: |
          echo 'uses: literal text'
          rm -rf logs
      - name: Setup
        uses: actions/cache@v4
  second:
    steps:
      - name: Setup
        uses: actions/checkout/subpath@v4
values: [same, same]
empty-map: {}
empty-seq: []
"""


def invoke(*args):
    return subprocess.run([str(BIN), "workflow", *args], capture_output=True,
                          text=True, timeout=20)


with tempfile.TemporaryDirectory(prefix="workflow-select-") as tmp:
    file = pathlib.Path(tmp) / "selectors.yml"
    file.write_text(SOURCE)

    def expect(verb, selector, stdout, status=0):
        out = invoke(verb, str(file), selector)
        assert out.returncode == status and out.stdout == stdout, (verb, selector, out)
        assert bool(out.stderr) == (status != 0), (selector, out)

    expect("get", "jobs.first.steps[1].if", "always()\n")
    expect("get", "jobs.first.steps[name=Cleanup logs].run",
           "echo 'uses: literal text'\nrm -rf logs\n\n")
    expect("get", "empty-map", "{}\n")
    expect("get", "empty-seq", "[]\n")
    expect("each", "jobs.*.steps[*].uses",
           "jobs.first.steps[0].uses\tactions/checkout@v4\n"
           "jobs.first.steps[2].uses\tactions/cache@v4\n"
           "jobs.second.steps[0].uses\tactions/checkout/subpath@v4\n")
    expect("each", "jobs.*.steps[uses^=actions/checkout].name",
           "jobs.first.steps[0].name\tSetup\njobs.second.steps[0].name\tSetup\n")
    expect("each", "jobs.first.steps[name=Cleanup logs]",
           "jobs.first.steps[1].name\tCleanup logs\n"
           "jobs.first.steps[1].if\talways()\n"
           "jobs.first.steps[1].run\techo 'uses: literal text'\nrm -rf logs\n\n")
    for selector in ["missing", "jobs.first", "values[*]", "jobs.first.steps[name=Setup].name"]:
        expect("get", selector, "", 1)
    for selector in ["missing", "jobs[*]", "values.*", "jobs.first.steps[uses^=echo].run",
                     "jobs.first.steps[name=Cleanup].name", "jobs.first.steps[99].name"]:
        expect("each", selector, "")
    for selector in ["", ".jobs", "jobs.", "jobs..first", "jobs[first]", "jobs[",
                     "jobs[-1]", "jobs[1.0]", "jobs[+1]", "jobs[0]trailing",
                     "jobs[name=]", "jobs[uses^=]", "jobs[run=echo]", "jobs[?(@.name)]",
                     "jobs['first']", 'jobs["first"]', "jobs[name=a[b]", "jobs[name=a\nb]",
                     "jobs[*].", "jobs**", "jobs.*[0:2]", " jobs"]:
        expect("each", selector, "", 2)
    for args in [[], ["get"], ["each", str(file)], ["get", str(file), "jobs", "extra"],
                 ["parse", str(file), "jobs"], ["other", str(file), "jobs"]]:
        out = invoke(*args)
        assert out.returncode == 2 and not out.stdout and "usage:" in out.stderr, (args, out)
    for verb in ["get", "each"]:
        out = invoke(verb, str(pathlib.Path(tmp) / "missing.yml"), "jobs")
        assert out.returncode == 2 and not out.stdout and "cannot read" in out.stderr, out
        file.write_text("jobs: [\n")
        out = invoke(verb, str(file), "jobs")
        assert out.returncode == 1 and not out.stdout and "refused" in out.stderr, out
    print("ok workflow selectors: every Pick, subtrees, order, cardinality, and refused grammar")
