const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trimEnd();
}

function changedFiles(base, head) {
  const names = base == null
    ? git(['ls-tree', '-r', '--name-only', '-z', head, '--', '*.dart'])
    : git(['diff', '--name-only', '-z', '--diff-filter=ACMR', base, head, '--', '*.dart']);
  return names.split('\0').filter(Boolean);
}

function workingTreeFiles() {
  const tracked = git([
    'diff', '--name-only', '-z', '--diff-filter=ACMR', 'HEAD', '--', '*.dart',
  ]);
  const untracked = git([
    'ls-files', '--others', '--exclude-standard', '-z', '--', '*.dart',
  ]);
  const trackedNames = tracked.split('\0').filter(Boolean);
  const untrackedNames = untracked.split('\0').filter(Boolean);
  return [...new Set([...trackedNames, ...untrackedNames])];
}

function compareTarget() {
  const { EVENT_NAME, BASE_REF, EVENT_BEFORE, COMMIT_SHA } = process.env;
  if (!COMMIT_SHA) throw new Error('GITHUB_SHA is required.');

  if (EVENT_NAME === 'pull_request') {
    if (!BASE_REF) throw new Error('GITHUB_BASE_REF is required for pull requests.');
    return [git(['merge-base', `origin/${BASE_REF}`, COMMIT_SHA]), COMMIT_SHA];
  }

  if (EVENT_NAME === 'push' && EVENT_BEFORE && !/^0+$/.test(EVENT_BEFORE)) {
    return [EVENT_BEFORE, COMMIT_SHA];
  }

  try {
    return [git(['rev-parse', `${COMMIT_SHA}^`]), COMMIT_SHA];
  } catch {
    return [null, COMMIT_SHA];
  }
}

try {
  const files = process.argv.includes('--working-tree')
    ? workingTreeFiles()
    : changedFiles(...compareTarget());
  const dartFiles = files.filter((file) => {
    // Preserve the existing untracked theme file until its owner approves cleanup.
    return file !== 'lib/theme/app_theme.dart';
  });

  if (dartFiles.length === 0) {
    console.log('No Dart files to format-check.');
    process.exit(0);
  }

  const dartArgs = ['format', '--output=none', '--set-exit-if-changed', ...dartFiles];
  const isWindows = process.platform === 'win32';
  let command = 'dart';
  if (isWindows) {
    const found = execFileSync('where.exe', ['dart'], { encoding: 'utf8' })
      .split(/\r?\n/)
      .find(Boolean);
    if (!found) throw new Error('Could not locate the Dart SDK executable.');
    const resolved = path.resolve(found);
    command = /\.bat$|\.cmd$/i.test(resolved) || path.basename(resolved) === 'dart'
      ? path.resolve(path.dirname(resolved), 'cache', 'dart-sdk', 'bin', 'dart.exe')
      : resolved;
    if (!fs.existsSync(command)) throw new Error(`Dart executable not found: ${command}`);
  }
  const result = spawnSync(command, dartArgs, { stdio: 'inherit' });
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
