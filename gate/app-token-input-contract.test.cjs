const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const vm = require('node:vm');

const [bin, root, bundlePath] = process.argv.slice(2);
assert(bin && root && bundlePath && process.argv.length === 5,
  'usage: node app-token-input-contract.test.cjs <mitos-gate> <repo-root> <bundle>');
const bundle = fs.readFileSync(bundlePath);
const blob = crypto.createHash('sha1').update(`blob ${bundle.length}\0`).update(bundle).digest('hex');
const revisions = {
  '6158842fe3bfd1a37b55273beb1805fc52f95120': '64ab729a6294000f5aa4a4bc0b73d1f32bc45510',
  '0b417b0da34b9946024230f28e98c9d99694d16f': 'd72941d797fd3113feb6b93fd0dec494b13a2547',
};
assert(revisions[blob], 'unreviewed bundle');
const source = bundle.toString('utf8');
function section(start, end) {
  assert.equal(source.split(start).length, 2, 'ambiguous bundle section');
  const offset = source.indexOf(start) + start.length;
  const finish = source.indexOf(end, offset);
  assert(finish > offset, 'bundle section missing');
  return source.slice(offset, finish);
}
const collector = section('// lib/get-permissions-from-inputs.js\n', '\n// ');
const main = section('// lib/main.js\n', '\n// lib/request.js');
const entry = source.slice(source.lastIndexOf('// main.js\n') + '// main.js\n'.length,
  source.indexOf('/*! Bundled license information:'));
assert(entry.includes('getPermissionsFromInputs(process.env)'), 'entrypoint bypasses collector');
assert(entry.includes('main('), 'entrypoint bypasses main');

const callers = [
  ['land-protection.yml', 'read', 1, { administration: 'read' }],
  ['update-prs.yml', 'rebase', 1, { contents: 'write', pull_requests: 'write', workflows: 'write' }],
];
async function checkCaller([file, job, index, expected], inherited = {}) {
  const leaves = execFileSync(bin, ['workflow', 'leaves', path.join(root, '.github/workflows', file)],
    { encoding: 'utf8' }).trim().split('\n').map(JSON.parse);
  const step = ['jobs', job, 'steps', index];
  const at = (leaf, suffix) => JSON.stringify(leaf.path) === JSON.stringify([...step, ...suffix]);
  assert.equal(leaves.find(leaf => at(leaf, ['uses'])).value,
    `actions/create-github-app-token@${revisions[blob]}`);
  const inputs = Object.fromEntries(leaves.filter(leaf => leaf.path.length === 6 &&
    JSON.stringify(leaf.path.slice(0, 5)) === JSON.stringify([...step, 'with']))
    .map(leaf => [leaf.path[5], leaf.value]));
  assert.equal(inputs['app-id'], '${{ vars.PR_UPDATER_APP_ID }}');
  assert.equal(inputs['private-key'], '${{ secrets.PR_UPDATER_APP_KEY }}');
  inputs['app-id'] = '1';
  inputs['private-key'] = 'dummy-not-a-private-key';
  const env = { GITHUB_REPOSITORY: 'kitimark/mitos', GITHUB_REPOSITORY_OWNER: 'kitimark', ...inherited };
  for (const [key, value] of Object.entries(inputs)) env[`INPUT_${key.toUpperCase()}`] = value;
  const calls = [];
  const saved = [];
  const getInput = key => env[`INPUT_${key.toUpperCase()}`] || '';
  const core = {
    getInput, getBooleanInput: key => getInput(key) === 'true', info() {}, setSecret() {},
    setOutput() {}, saveState: (key, value) => saved.push([key, value]),
    setFailed: message => { throw new Error(message); },
  };
  const request = async (route, options) => {
    assert.equal(route, 'GET /repos/{owner}/{repo}/installation');
    assert.equal(options.owner, 'kitimark');
    assert.equal(options.repo, 'mitos');
    calls.push('installation-read-stub');
    return { data: { id: 1, app_slug: 'dummy' } };
  };
  const createAppAuth = options => {
    assert.equal(options.appId, '1');
    assert.equal(options.privateKey, 'dummy-not-a-private-key');
    const auth = async options => {
      calls.push(JSON.parse(JSON.stringify(options)));
      return { token: 'dummy-local-result', expiresAt: '2099-01-01T00:00:00Z' };
    };
    auth.hook = () => { throw new Error('request hook must not execute'); };
    return auth;
  };
  const sandbox = {
    process: { env }, core_exports: core, import_core2: { default: core },
    getInput, getBooleanInput: core.getBooleanInput, setFailed: core.setFailed,
    createAppAuth, request_default: request, pRetry: operation => operation(),
    isNetworkError: () => false, ensureNativeProxySupport() {},
    console: { error: error => { throw error; } },
  };
  const context = vm.createContext(sandbox, { codeGeneration: { strings: false, wasm: false } });
  vm.runInContext(collector + main + entry, context, { timeout: 1000 });
  await context.main_default;
  assert.equal(calls.length, 2);
  assert.equal(calls[1].type, 'installation');
  assert.equal(calls[1].installationId, 1);
  assert.deepEqual(calls[1].repositoryNames, ['mitos']);
  assert.deepEqual(calls[1].permissions, expected, `${file}: permission narrowing`);
  assert.deepEqual(saved.map(([key]) => key), ['token', 'expiresAt'], 'revoke state omitted');
}
(async () => {
  for (const caller of callers) {
    await checkCaller(caller);
    await checkCaller(caller, { INPUT_PERMISSION_ADMINISTRATION: 'write', INPUT_PERMISSION_CONTENTS: 'write' });
  }
  console.log('4 bundled permission-map controls passed (offline stubs; dependency initialization excluded)');
})().catch(error => { console.error(error); process.exitCode = 1; });
