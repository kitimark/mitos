import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

BIN = pathlib.Path(sys.argv[1]).resolve()
ROOT = pathlib.Path(sys.argv[2]).resolve()
SOURCE = ROOT / '.github/workflows'
passed = 0


def invoke(root):
    return subprocess.run([str(BIN), 'workflow', 'pins', str(root)],
                          capture_output=True, text=True, timeout=30)


def check(root, reason=None, status=1):
    global passed
    result = invoke(root)
    wanted = status if reason else 0
    assert result.returncode == wanted, ('exit', wanted, result.returncode, result.stderr)
    assert not result.stdout, 'unexpected stdout'
    if reason:
        assert result.stderr == f'workflow pins: {reason}\n', ('reason', result.stderr)
    else:
        assert not result.stderr, 'unexpected stderr'
    passed += 1


def change(text, old, new, occurrence=0):
    offset = 0
    for _ in range(occurrence + 1):
        found = text.find(old, offset)
        assert found >= 0, 'mutation anchor missing'
        offset = found + len(old)
    return text[:found] + new + text[offset:]


with tempfile.TemporaryDirectory(prefix='workflow-pins-') as scratch:
    scratch = pathlib.Path(scratch)
    check(ROOT)

    def case(name, file, mutate, reason=None, status=1):
        folder = scratch / name
        shutil.copytree(SOURCE, folder / '.github/workflows')
        path = folder / '.github/workflows' / file
        path.write_text(mutate(path.read_text()))
        check(folder, f'refused {reason}' if reason else None, status)

    case('finalLandAccepts', 'land.yml', lambda s: s)
    old_if = "    if: >-\n      github.ref == 'refs/heads/main' && github.run_attempt == '1' &&\n      needs.decide.outputs.pr != ''"
    case('apply-or', 'land.yml', lambda s: change(s, old_if, old_if.replace(' && ', ' || ', 1)), 'land.apply-condition')
    case('apply-comment', 'land.yml', lambda s: change(s, old_if,
         "    # github.run_attempt == '1'\n    if: >-\n      github.ref == 'refs/heads/main' && needs.decide.outputs.pr != ''"), 'land.apply-condition')
    case('apply-map', 'land.yml', lambda s: change(s, old_if,
         "    if:\n      nested: github.ref == 'refs/heads/main' && github.run_attempt == '1' && needs.decide.outputs.pr != ''"), 'land.apply-condition')
    case('apply-literal-space', 'land.yml', lambda s: change(s, old_if, old_if.replace('heads/main', 'heads/ main')), 'land.apply-condition')
    case('permissions-text', 'land.yml', lambda s: change(s, 'permissions: {}', "permissions: '{}'"), 'land.shape')
    case('permissions-seq', 'land.yml', lambda s: change(s, 'permissions: {}', 'permissions: []'), 'land.shape')
    case('extra-job', 'land.yml', lambda s: s + '\n  other: {}\n', 'land.shape')
    case('permission-write', 'land.yml', lambda s: change(s, '      actions: read', '      actions: write'), 'land.decide')
    case('permission-extra', 'land.yml', lambda s: change(s, '      actions: read', '      actions: read\n      deployments: read'), 'land.decide')
    case('permission-missing', 'land.yml', lambda s: change(s, '      actions: read\n', ''), 'land.decide')
    case('decide-cancel', 'land.yml', lambda s: change(s, '      cancel-in-progress: false', '      cancel-in-progress: true'), 'land.decide')
    for name, expression in [
            ('bracket', "secrets['OTHER']"), ('aggregate', 'toJSON(secrets)'),
            ('mixed-case', 'SeCrEtS.OTHER'), ('spaced-bracket', "sEcReTs [ 'OTHER' ]")]:
        case('decide-secret-' + name, 'land.yml', lambda s, e=expression: change(s,
             '    env:\n      LAND_PROVENANCE_ISSUE:', '    env:\n      EXTRA: ${{ ' + e + ' }}\n      LAND_PROVENANCE_ISSUE:'), 'land.decide')
        case('global-secret-' + name, 'land.yml', lambda s, e=expression: change(s,
             'env:\n', 'env:\n  EXTRA: ${{ ' + e + ' }}\n'), 'land.scope')
    case('secret-key', 'land.yml', lambda s: change(s, 'env:\n', 'env:\n  SeCrEtS: data\n'), 'land.scope')
    case('extra-step', 'land.yml', lambda s: change(s, '      - id: t0', '      - run: other\n      - id: t0'), 'land.decide')
    checkout = 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262'
    cache = 'actions/cache/restore@0057852bfaa89a56745cba8c7296529d2fc39830'
    upload = 'actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02'
    for name, old, new, number in [
            ('checkout', checkout, 'actions/checkout@v4', 0),
            ('cache', cache, 'actions/cache/restore@v4', 0),
            ('record-upload', upload, 'actions/upload-artifact@v4', 0),
            ('reads-upload', upload, 'actions/upload-artifact@v4', 1)]:
        case('floating-' + name, 'land.yml', lambda s, o=old, n=new, i=number: change(s, o, n, i), 'land.decide')
    case('wrong-sha', 'land.yml', lambda s: change(s, cache, 'actions/cache/restore@' + '0' * 40), 'land.decide')
    case('checkout-credentials', 'land.yml', lambda s: change(s, '          persist-credentials: false', '          persist-credentials: true'), 'land.decide')
    case('decide-condition', 'land.yml', lambda s: change(s, "github.event.comment.user.login == github.repository_owner", 'true'), 'land.decide')
    for name, expression in [('token', "github['token']"), ('context', 'toJSON(github)'),
                              ('event', "github['event']"), ('mixed-case', "GiThUb['ToKeN']")]:
        case('dashboard-context-' + name, 'land.yml', lambda s, e=expression: change(s,
             '      LAND_PROVENANCE_ISSUE: 586', '      LAND_PROVENANCE_ISSUE: ${{ ' + e + ' }}'), 'land.decide')
        case('output-context-' + name, 'land.yml', lambda s, e=expression: change(s,
             '      pr: ${{ steps.decide.outputs.pr }}', '      pr: ${{ ' + e + ' }}'), 'land.decide')
        case('root-env-context-' + name, 'land.yml', lambda s, e=expression: change(s,
             'env:\n', 'env:\n  EXTRA: ${{ ' + e + ' }}\n'), 'land.scope')
    case('retired-dashboard-key', 'land.yml', lambda s: s.replace('LAND_PROVENANCE_ISSUE', 'LAND_DASHBOARD'), 'land.decide')
    case('root-name-context', 'land.yml', lambda s: change(s, 'name: land', 'name: ${{ toJSON(github) }}'), 'land.shape')
    case('root-run-name-context', 'land.yml', lambda s: change(s, 'name: land', "name: land\nrun-name: ${{ github['token'] }}"), 'land.shape')
    for job, occurrence in [('decide', 0), ('apply', 1), ('report', 2)]:
        case(job + '-runner-context', 'land.yml', lambda s, i=occurrence: change(s,
             '    runs-on: ubuntu-24.04', "    runs-on: ${{ github['token'] }}", i), 'land.' + job)
    for job, value, occurrence in [('decide', '15', 0), ('apply', '5', 0), ('report', '5', 1)]:
        case(job + '-timeout-context', 'land.yml', lambda s, v=value, i=occurrence: change(s,
             '    timeout-minutes: ' + v, '    timeout-minutes: ${{ toJSON(github) }}', i), 'land.' + job)
    for name, anchor in [('path', '            ~/.elan'), ('key', '          key: lean-'),
                          ('restore-key', '          restore-keys: lean-')]:
        case('cache-' + name + '-context', 'land.yml', lambda s, a=anchor: change(s,
             a, a.replace('~/.elan', "${{ github['token'] }}").replace('lean-', "${{ github['token'] }}lean-")), 'land.decide')
    case('apply-output-context', 'land.yml', lambda s: change(s,
         '      outcome: ${{ steps.apply.outputs.outcome }}', '      outcome: ${{ toJSON(github) }}'), 'land.apply')
    case('report-condition-context', 'land.yml', lambda s: change(s,
         "      always() && github.ref", "      ${{ github['event'] }} && github.ref"), 'land.report')
    case('report-needs-context', 'land.yml', lambda s: change(s,
         '    needs: [decide, apply]', "    needs: ${{ github['token'] }}"), 'land.report')
    case('event-other-job', 'land.yml', lambda s: change(s, '          LAND_ANSWERS:', '          EXTRA: ${{ github.event.comment.body }}\n          LAND_ANSWERS:'), 'land.report')
    case('event-other-output', 'land.yml', lambda s: change(s, '      pr: ${{ steps.decide.outputs.pr }}', '      other: ${{ github.event.comment.body }}\n      pr: ${{ steps.decide.outputs.pr }}'), 'land.decide')
    case('multiline-run', 'land.yml', lambda s: change(s, '      - run: .github/scripts/install-elan.sh', '      - run: |\n          .github/scripts/install-elan.sh\n          other'), 'land.decide')
    case('token-other-site', 'land.yml', lambda s: change(s, '    env:\n      LAND_PROVENANCE_ISSUE:', '    env:\n      OTHER: ${{ github.token }}\n      LAND_PROVENANCE_ISSUE:'), 'land.decide')
    case('top-concurrency', 'land.yml', lambda s: change(s, 'permissions: {}', 'concurrency: other\npermissions: {}'), 'land.shape')
    case('apply-concurrency', 'land.yml', lambda s: change(s, '      group: land-apply', '      group: other'), 'land.apply')
    case('apply-token-binding', 'land.yml', lambda s: change(s, '          LAND_MERGE_TOKEN: ${{ steps.app.outputs.token }}', '          LAND_MERGE_TOKEN: ${{ github.token }}'), 'land.apply')
    case('apply-requires-spec', 'land.yml', lambda s: change(s, '          LAND_REQUIRES_SPEC: ${{ needs.decide.outputs.requires_spec }}', '          LAND_REQUIRES_SPEC: false'), 'land.apply')
    case('switch-override', 'land.yml', lambda s: change(s, '    env:\n      LAND_PROVENANCE_ISSUE:', "    env:\n      LAND_MERGE: 'on'\n      LAND_PROVENANCE_ISSUE:"), 'land.decide')
    case('report-write', 'land.yml', lambda s: change(s, '      pull-requests: write', '      pull-requests: read'), 'land.report')
    case('protection-permission-type', 'land-protection.yml', lambda s: change(s, 'permissions: {}', "permissions: '{}'"), 'protection.permissions')
    case('protection-extra-job', 'land-protection.yml', lambda s: s + '\n  other: {}\n', 'protection.jobs')
    case('protection-condition', 'land-protection.yml', lambda s: change(s, "github.event_name == 'push'", "github.event_name == 'other'"), 'protection.condition')
    case('protection-action', 'land-protection.yml', lambda s: change(s, checkout, 'actions/checkout@v4'), 'protection.steps')
    case('protection-extra-permission', 'land-protection.yml', lambda s: change(s, '      contents: read', '      contents: read\n      actions: read'), 'protection.permissions')
    case('protection-trigger', 'land-protection.yml', lambda s: change(s, '    branches: [main]', '    branches: [other]'), 'protection.triggers')

    def swap_protection(s, first, second, end=None):
        a = s.index(first)
        b = s.index(second, a)
        c = s.index(end, b) if end else len(s)
        return s[:a] + s[b:c] + s[a:b] + s[c:]

    case('read-before-mint', 'land-protection.yml', lambda s: swap_protection(s,
         '      - name: Mint', '      - name: Read', '      - uses: actions/upload'), 'protection.steps')
    case('upload-before-read', 'land-protection.yml', lambda s: swap_protection(s,
         '      - name: Read', '      - uses: actions/upload'), 'protection.steps')
    case('protection-secret', 'land-protection.yml', lambda s: change(s, '          GH_TOKEN: ${{ steps.app.outputs.token }}', '          GH_TOKEN: ${{ secrets.OTHER }}'), 'protection.steps')

    mint = '''jobs:
  check:
    environment: trusted
    steps:
      - uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510
        with:
          permission-contents: read
'''
    for name, text, reason in [
        ('mint-extra-plain', mint, 'mint.inventory'),
        ('mint-step-shape', mint.replace('      - uses:', '      - id: {}\n        uses:'), 'mint.shape'),
        ('mint-outside-trusted', mint.replace('    environment: trusted\n', ''), 'mint.authority'),
        ('mint-floating', mint.replace('@64ab729a6294000f5aa4a4bc0b73d1f32bc45510', '@v1'), 'mint.authority'),
        ('mint-extra-scope', mint.replace('          permission-contents:', '          owner: other\n          permission-contents:'), 'mint.authority'),
        ('mint-permission-outside', mint.replace('        with:', '        env:\n          permission-contents: write\n        with:'), 'mint.authority'),
        ('mint-no-permission', mint.replace('          permission-contents: read', '          app-id: app'), 'mint.authority'),
        ('mint-wrong-type', mint.replace('          permission-contents: read', '          permission-contents: {}'), 'mint.authority'),
        ('mint-unsupported-permission', mint.replace('permission-contents: read', 'permission-issues: write'), 'mint.authority')]:
        folder = scratch / name
        shutil.copytree(SOURCE, folder / '.github/workflows')
        (folder / '.github/workflows/extra.yaml').write_text(text)
        check(folder, f'refused {reason}' if reason else None)

    closed_mints = [
        ('root-env', 'env:\n  INPUT_PERMISSION_ADMINISTRATION: write\n' + mint),
        ('job-env', mint.replace('    environment:',
             '    env:\n      INPUT_PERMISSION_ADMINISTRATION: write\n    environment:')),
        ('step-env', mint.replace('        with:',
             '        env:\n          INPUT_PERMISSION_ADMINISTRATION: write\n        with:')),
        ('earlier-env-file', mint.replace('      - uses:',
             '      - run: echo "INPUT_PERMISSION_ADMINISTRATION=write" >> "$GITHUB_ENV"\n      - uses:')),
        ('underscore-with', mint.replace('        with:',
             '        with:\n          permission_administration: write'))]
    for name, text in closed_mints:
        folder = scratch / ('mint-closed-' + name)
        shutil.copytree(SOURCE, folder / '.github/workflows')
        (folder / '.github/workflows/extra.yml').write_text(text)
        check(folder, 'refused mint.inventory')
    for file in ['ci.yml', 'owner-ping.yml']:
        case('mint-in-' + file, file, lambda s: s + mint.removeprefix('jobs:'), 'mint.inventory')
    folder = scratch / 'safe-nonmint-workflow'
    shutil.copytree(SOURCE, folder / '.github/workflows')
    (folder / '.github/workflows/extra.yaml').write_text('jobs:\n  check:\n    steps:\n      - run: true\n')
    check(folder)

    for file, job, step_reason, root_reason, job_reason, earlier_name in [
            ('land.yml', 'apply', 'land.apply', 'land.scope', 'land.shape', 'landEarlierEnvWriterRefuses'),
            ('land-protection.yml', 'read', 'protection.steps', 'protection.jobs', 'protection.jobs', 'protectionEarlierEnvWriterRefuses'),
            ('update-prs.yml', 'rebase', 'mint.updater', 'mint.updater', 'mint.updater', 'updaterEarlierEnvWriterRefuses')]:
        case('owned-mint-root-env-' + job, file, lambda s: 'env:\n  INPUT_PERMISSION_ADMINISTRATION: write\n' + s
             if not s.startswith('name: land\n') else change(s, "  LAND_MERGE: 'on'", "  LAND_MERGE: 'on'\n  INPUT_PERMISSION_ADMINISTRATION: write"), root_reason)
        case('owned-mint-job-env-' + job, file, lambda s, j=job: change(s,
             '  ' + j + ':\n', '  ' + j + ':\n    env:\n      INPUT_PERMISSION_ADMINISTRATION: write\n'), job_reason)
        case('owned-mint-step-env-' + job, file, lambda s: change(s,
             '        uses: actions/create-github-app-token@',
             '        env:\n          INPUT_PERMISSION_ADMINISTRATION: write\n        uses: actions/create-github-app-token@'), step_reason)
        case('owned-mint-underscore-with-' + job, file, lambda s: change(s,
             '          app-id:', '          permission_administration: write\n          app-id:'), step_reason)
        case(earlier_name, file, lambda s: change(s,
             '      - name: Mint',
             '      - run: echo "INPUT_PERMISSION_ADMINISTRATION=write" >> "$GITHUB_ENV"\n      - name: Mint'), step_reason)
    case('updater-token', 'update-prs.yml', lambda s: change(s, '          token: ${{ steps.app.outputs.token }}', '          token: ${{ github.token }}'), 'mint.updater')
    case('updater-extra-mint', 'update-prs.yml', lambda s: s + '\n      - uses: actions/create-github-app-token@64ab729a6294000f5aa4a4bc0b73d1f32bc45510\n        with:\n          permission-contents: read\n', 'mint.updater')
    for name, expression in [
            ('indexed', "steps['app']['outputs']['token']"), ('aggregate', 'toJSON(steps)'),
            ('mixed-case', "StEpS['app'].outputs.token")]:
        ref = '${{ ' + expression + ' }}'
        mutations = [
            ('extra-step', lambda s, v=ref: s + '\n      - run: true\n        env:\n          EXTRA: ' + v + '\n'),
            ('root-env', lambda s, v=ref: 'env:\n  EXTRA: ' + v + '\n' + s),
            ('root-output', lambda s, v=ref: 'outputs:\n  EXTRA: ' + v + '\n' + s),
            ('root-name', lambda s, v=ref: change(s, 'name: Keep PR branches up to date', 'name: ' + v)),
            ('root-run-name', lambda s, v=ref: 'run-name: ' + v + '\n' + s),
            ('job-env', lambda s, v=ref: change(s, '  rebase:\n', '  rebase:\n    env:\n      EXTRA: ' + v + '\n')),
            ('job-output', lambda s, v=ref: change(s, '  rebase:\n', '  rebase:\n    outputs:\n      EXTRA: ' + v + '\n')),
            ('job-runner', lambda s, v=ref: change(s, '    runs-on: ubuntu-24.04', '    runs-on: ' + v)),
            ('config-env', lambda s, v=ref: change(s, '          APP_ID:', '          EXTRA: ' + v + '\n          APP_ID:')),
            ('config-run', lambda s, v=ref: change(s, '          if [ -z "$APP_ID" ]', '          echo ' + v + '\n          if [ -z "$APP_ID" ]')),
            ('mint-input', lambda s, v=ref: change(s, '          app-id: ${{ vars.PR_UPDATER_APP_ID }}', '          app-id: ' + v)),
            ('checkout-input', lambda s, v=ref: change(s, '          fetch-depth: 0', '          fetch-depth: ' + v)),
            ('rebase-env', lambda s, v=ref: change(s, '          GH_TOKEN:', '          EXTRA: ' + v + '\n          GH_TOKEN:'))]
        for site, mutate in mutations:
            case('updater-' + site + '-' + name, 'update-prs.yml', mutate, 'mint.updater')
    case('updater-config-changed', 'update-prs.yml', lambda s: change(s,
         'echo "ok=true"', 'echo "ok=false"'), 'mint.updater')
    case('safe-updater-map-order', 'update-prs.yml', lambda s: change(s,
         '          APP_ID: ${{ vars.PR_UPDATER_APP_ID }}\n          APP_KEY: ${{ secrets.PR_UPDATER_APP_KEY }}',
         '          APP_KEY: ${{ secrets.PR_UPDATER_APP_KEY }}\n          APP_ID: ${{ vars.PR_UPDATER_APP_ID }}'))
    ci_types = '[opened, synchronize, reopened, labeled, unlabeled]'
    ci_push = '  push:\n    branches: [main]\n'
    ci_pr = '  pull_request:\n    types: ' + ci_types + '\n'
    ci_on = 'on:\n' + ci_push + ci_pr
    trigger_mutations = [
        ('label-only', ci_on.replace(ci_types, '[labeled, unlabeled]')),
        ('on-absent', ''), ('on-empty', 'on: {}\n'),
        ('on-scalar', 'on: push\n'), ('on-sequence', 'on: [push, pull_request]\n'),
        ('push-absent', 'on:\n' + ci_pr), ('pr-absent', 'on:\n' + ci_push),
        ('wrong-main', ci_on.replace('[main]', '[other]')),
        ('main-absent', ci_on.replace('[main]', '[]')),
        ('extra-branch', ci_on.replace('[main]', '[main, other]')),
        ('branch-scalar', ci_on.replace('[main]', 'main')),
        ('push-default', ci_on.replace(ci_push, '  push:\n')),
        ('pr-default', ci_on.replace(ci_pr, '  pull_request:\n')),
        ('pr-empty', ci_on.replace(ci_pr, '  pull_request: {}\n')),
        ('pr-scalar', ci_on.replace(ci_pr, '  pull_request: opened\n')),
        ('pr-sequence', ci_on.replace(ci_pr, '  pull_request: [opened]\n')),
        ('extra-event', ci_on + '  workflow_dispatch: {}\n')]
    for activity in ['opened', 'synchronize', 'reopened', 'labeled', 'unlabeled']:
        remaining = [value for value in ['opened', 'synchronize', 'reopened', 'labeled', 'unlabeled']
                     if value != activity]
        trigger_mutations.append(('missing-' + activity,
                                  ci_on.replace(ci_types, '[' + ', '.join(remaining) + ']')))
    for name, value in [('empty', '[]'), ('scalar', 'opened'), ('map', '{}'),
                        ('nontext', '\n      - opened\n      - synchronize\n      - reopened\n      - labeled\n      - other: value'),
                        ('duplicate', '[opened, opened, reopened, labeled, unlabeled]'),
                        ('extra', '[opened, synchronize, reopened, labeled, unlabeled, edited]')]:
        trigger_mutations.append(('types-' + name, ci_on.replace(ci_types, value)))
    for event, filters in [('push', ['paths', 'paths-ignore', 'branches-ignore', 'tags', 'tags-ignore']),
                           ('pull_request', ['paths', 'paths-ignore', 'branches', 'branches-ignore'])]:
        for key in filters:
            trigger_mutations.append((event + '-' + key,
                                      change(ci_on, '  ' + event + ':\n',
                                             '  ' + event + ':\n    ' + key + ': [never-match]\n')))
    for name, trigger in trigger_mutations:
        case('ci-trigger-' + name, 'ci.yml', lambda s, value=trigger: change(s, ci_on, value), 'ci.trigger')
    case('safe-ci-trigger-activity-order', 'ci.yml', lambda s: change(s, ci_types,
         '[unlabeled, labeled, reopened, synchronize, opened]'))
    case('safe-ci-trigger-map-order', 'ci.yml', lambda s: change(s, ci_on, 'on:\n' + ci_pr + ci_push))

    ci_step = '      - name: Every app token is narrowed in trusted\n        run: .github/scripts/app-token.test.sh\n'
    build_step = '      - name: Build core and gate\n        run: lake build\n'
    case('ci-before-build', 'ci.yml', lambda s: change(s.replace(ci_step, '', 1), build_step, ci_step + build_step), 'ci.schedule')
    case('ci-duplicate', 'ci.yml', lambda s: change(s, ci_step, ci_step + ci_step), 'ci.schedule')
    case('ci-missing', 'ci.yml', lambda s: change(s, ci_step, ''), 'ci.schedule')
    case('ci-skipped', 'ci.yml', lambda s: change(s, ci_step, ci_step.replace('        run:', '        if: false\n        run:')), 'ci.schedule')
    ci_if = "    if: >-\n      github.event_name == 'push' ||\n      (github.event_name == 'pull_request' &&\n       github.event.action != 'labeled' &&\n       github.event.action != 'unlabeled')\n"
    for name, replacement in [('false', '    if: false\n'), ('absent', ''),
                              ('map', '    if:\n      nested: false\n'),
                              ('or', ci_if.replace("github.event.action != 'labeled' &&", "github.event.action != 'labeled' ||"))]:
        case('ci-job-if-' + name, 'ci.yml', lambda s, r=replacement: change(s, ci_if, r), 'ci.schedule')
    for key, value in [('continue-on-error', 'true'), ('defaults', '\n      run:\n        shell: true {0}'),
                       ('strategy', '\n      matrix:\n        skip: [true]'), ('DEFAULTS', '{}')]:
        case('ci-job-' + key, 'ci.yml', lambda s, k=key, v=value: change(s,
             '  checks:\n', '  checks:\n    ' + k + ': ' + v + '\n'), 'ci.schedule')
    for key in ['defaults', 'DeFaUlTs']:
        case('ci-global-' + key, 'ci.yml', lambda s, k=key: change(s, 'permissions: {}',
             k + ':\n  run:\n    shell: true {0}\npermissions: {}'), 'ci.schedule')
    checks_env = "    env:\n      LAKE_NO_CACHE: '1'\n"
    for name, key, value in [
            ('bash-hook', 'env', "\n  BASH_ENV: $(printf 'exit 0\\n' > /tmp/workflow-pin-hook)/tmp/workflow-pin-hook"),
            ('node-options', 'env', '\n  NODE_OPTIONS: --require=/tmp/hook'),
            ('harmless', 'env', '\n  DATA: harmless'), ('empty', 'env', '{}'),
            ('case', 'EnV', '\n  DATA: harmless')]:
        case('ci-inherited-env-' + name, 'ci.yml', lambda s, k=key, v=value: change(s,
             'permissions: {}', k + ': ' + v + '\npermissions: {}'), 'ci.schedule')
        if name == 'empty':
            mut = lambda s: change(s, checks_env, '    env: {}\n')
        elif name == 'case':
            mut = lambda s: change(s, checks_env, "    EnV:\n      LAKE_NO_CACHE: '1'\n")
        else:
            mut = lambda s, v=value: change(s, checks_env, checks_env.rstrip('\n') + v.replace('\n  ', '\n      ') + '\n')
        case('ci-job-env-' + name, 'ci.yml', mut, 'ci.schedule')
    case('ci-job-env-missing', 'ci.yml', lambda s: change(s, checks_env, ''), 'ci.schedule')
    case('ci-job-env-zero', 'ci.yml', lambda s: change(s, checks_env, "    env:\n      LAKE_NO_CACHE: '0'\n"), 'ci.schedule')
    case('land-decide-no-cache-missing', 'land.yml', lambda s: change(s, "      LAKE_NO_CACHE: '1'\n", ''), 'land.decide')
    case('land-decide-no-cache-zero', 'land.yml', lambda s: change(s, "      LAKE_NO_CACHE: '1'\n", "      LAKE_NO_CACHE: '0'\n"), 'land.decide')
    for step_name, step in [('build', build_step), ('test', ci_step)]:
        for name, key, value in [
                ('bash-hook', 'env', "\n          BASH_ENV: $(printf 'exit 0\\n' > /tmp/workflow-pin-hook)/tmp/workflow-pin-hook"),
                ('node-options', 'env', '\n          NODE_OPTIONS: --require=/tmp/hook'),
                ('harmless', 'env', '\n          DATA: harmless'), ('empty', 'env', '{}'),
                ('case', 'EnV', '\n          DATA: harmless')]:
            case('ci-' + step_name + '-env-' + name, 'ci.yml', lambda s, st=step, k=key, v=value: change(s,
                 st, st.replace('        run:', '        ' + k + ': ' + v + '\n        run:')), 'ci.schedule')
    for suite in ['land-protection', 'land-decide', 'land-apply', 'land-report']:
        case('ci-' + suite + '-env-hook', 'ci.yml', lambda s, name=suite: change(s,
             '        run: .github/scripts/' + name + '.test.sh\n',
             '        run: .github/scripts/' + name + '.test.sh\n        env:\n          BASH_ENV: /tmp/hook\n'), 'ci.schedule')
    case('ci-step-unknown-control', 'ci.yml', lambda s: change(s, build_step,
         build_step.replace('        run:', '        unknown-control: true\n        run:')), 'ci.schedule')
    case('ci-step-name-shape', 'ci.yml', lambda s: change(s, build_step,
         build_step.replace('name: Build core and gate', 'name:\n          nested: Build core and gate')), 'ci.schedule')
    case('safe-ci-step-name', 'ci.yml', lambda s: change(s, ci_step,
         ci_step.replace('Every app token is narrowed in trusted', 'A harmless test name')))
    case('safe-ci-step-order', 'ci.yml', lambda s: change(s, build_step,
         '      - run: lake build\n        name: Build core and gate\n'))

    def remove_ci_steps(s):
        first = s.index('    steps:\n', s.index('  checks:\n'))
        boundary = re.search(r'^  [A-Za-z0-9_-]+:[ \t]*$', s[first:], re.MULTILINE)
        assert boundary is not None, 'next CI job missing'
        end = first + boundary.start()
        mutated = s[:first] + s[end:]
        jobs = r'^  ([A-Za-z0-9_-]+):[ \t]*$'
        assert re.findall(jobs, mutated, re.MULTILINE) == re.findall(jobs, s, re.MULTILINE)
        return mutated

    case('ci-steps-absent', 'ci.yml', remove_ci_steps, 'ci.steps')
    case('ci-steps-and-trigger-absent', 'ci.yml', lambda s:
         change(remove_ci_steps(s), ci_on, ''), 'ci.steps')
    case('owner-ping-drift', 'owner-ping.yml', lambda s: change(s, 'name: Comment with the first line of the latest catch-up', 'name: different', 1), 'owner-ping.steps')
    folder = scratch / 'owner-ping-anchor'
    shutil.copytree(SOURCE, folder / '.github/workflows')
    path = folder / '.github/workflows/owner-ping.yml'
    path.write_text(change(path.read_text(), '      - name: Comment', '      - &ping\n        name: Comment'))
    check(folder, 'reader-refusal')
    case('safe-comment', 'land.yml', lambda s: '# harmless comment\n' + s)
    case('safe-map-order', 'land.yml', lambda s: change(s, '      contents: read\n      pull-requests: read', '      pull-requests: read\n      contents: read'))
    case('safe-quoted-value', 'land-protection.yml', lambda s: change(s, '    timeout-minutes: 5', "    timeout-minutes: '5'"))
    case('safe-identifier-prefix', 'land.yml', lambda s: change(s,
         '      LAND_PROVENANCE_ISSUE: 586', '      LAND_PROVENANCE_ISSUE: secretsauce other_secrets'))
    sentinel = scratch / 'must-not-execute'
    case('safe-log-data', 'land.yml', lambda s: change(s, '      LAND_PROVENANCE_ISSUE: 586',
         f'      LAND_PROVENANCE_ISSUE: "##[error]data $(touch {sentinel})"'))
    assert not sentinel.exists(), 'workflow scalar executed'

    for name in ['land.yml', 'land-protection.yml', 'ci.yml', 'update-prs.yml', 'owner-ping.yml']:
        folder = scratch / ('missing-' + name)
        shutil.copytree(SOURCE, folder / '.github/workflows')
        (folder / '.github/workflows' / name).unlink()
        check(folder, 'required workflow missing', 2)
    folder = scratch / 'file-io'
    shutil.copytree(SOURCE, folder / '.github/workflows')
    (folder / '.github/workflows/bad.yaml').mkdir()
    check(folder, 'workflow file IO error', 2)
    check(scratch / 'absent-##[error]path', 'workflow directory IO error', 2)
    folder = scratch / 'reader-refusal'
    shutil.copytree(SOURCE, folder / '.github/workflows')
    (folder / '.github/workflows/extra.yml').write_text('jobs:\n  bad:\n    steps:\n      - run: *alias\n')
    check(folder, 'reader-refusal')
    for args in [['pins'], ['pins', str(ROOT), 'extra']]:
        result = subprocess.run([str(BIN), 'workflow', *args], capture_output=True, text=True, timeout=30)
        assert result.returncode == 2 and not result.stdout, 'usage must exit 2 without stdout'
        passed += 1

    timings = []
    for _ in range(5):
        start = time.perf_counter()
        for _ in range(5):
            check(ROOT)
        timings.append(time.perf_counter() - start)
    print(f'{passed} workflow pin checks passed; five complete calls in seconds: ' +
          ', '.join(f'{value:.3f}' for value in timings))
