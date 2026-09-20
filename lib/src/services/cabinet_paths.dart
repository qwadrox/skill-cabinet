import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/library.dart';

// Where everything lives, relative to one home directory. Services take
// it explicitly so tests (and SKILL_CABINET_HOME) can run against a
// throwaway home. Plain strings only: services run on background isolates.
class CabinetPaths {
  const CabinetPaths(this.home);

  // SKILL_CABINET_HOME overrides $HOME, for trying the app on sample data.
  factory CabinetPaths.fromEnvironment() {
    final env = Platform.environment;
    return CabinetPaths(env['SKILL_CABINET_HOME'] ?? env['HOME'] ?? Directory.current.path);
  }

  final String home;

  String get cabinetDir => p.join(home, cabinetDirName);
  String get storeDir => p.join(cabinetDir, 'skills');
  String get collectionsFile => p.join(cabinetDir, 'collections.json');
  String get deploymentFile => p.join(cabinetDir, 'deployment.json');
  String get gitSourcesFile => p.join(cabinetDir, 'git_sources.json');
  String get githubSourcesFile => p.join(cabinetDir, 'github_sources.json');

  String inHome(String relative) => p.join(home, relative);

  // A folder the user wrote down: ~/..., an absolute path, or (as the
  // catalog writes them) a path relative to home.
  String resolveUser(String raw) {
    final value = raw.trim();
    if (value == '~') return home;
    if (value.startsWith('~/')) return p.normalize(p.join(home, value.substring(2)));
    if (p.isAbsolute(value)) return p.normalize(value);
    return p.normalize(p.join(home, value));
  }

  // Display form: ~/... for anything under home.
  String tilde(String full) {
    if (full == home) return '~';
    if (p.isWithin(home, full)) return '~/${p.relative(full, from: home)}';
    return full;
  }
}
