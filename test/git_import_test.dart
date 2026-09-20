import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skill_cabinet/src/domain/git_import.dart';
import 'package:skill_cabinet/src/services/cabinet_paths.dart';
import 'package:skill_cabinet/src/services/git_import_service.dart';

void main() {
  test('accepts HTTPS, SSH, and SCP-style Git URLs', () {
    const service = GitImportService(CabinetPaths('/tmp/cabinet'));
    expect(service.validateRemoteUrl('https://github.com/acme/skills.git'), contains('github.com'));
    expect(service.validateRemoteUrl('ssh://git@git.example.com/acme/skills'), startsWith('ssh://'));
    expect(service.validateRemoteUrl('git@git.example.com:acme/skills.git'), startsWith('git@'));
  });

  test('rejects embedded credentials, local paths, and GitHub folder pages', () {
    const service = GitImportService(CabinetPaths('/tmp/cabinet'));
    expect(
      () => service.validateRemoteUrl('https://user:secret@example.com/acme/skills'),
      throwsA(isA<GitImportException>()),
    );
    expect(() => service.validateRemoteUrl('/tmp/skills'), throwsA(isA<GitImportException>()));
    expect(
      () => service.validateRemoteUrl('https://github.com/acme/skills/tree/main/agents'),
      throwsA(isA<GitImportException>()),
    );
  });

  test('source records round-trip through JSON', () {
    const record = GitSourceRecord(
      skillName: 'reviewer',
      sourceUrl: 'https://git.example.com/acme/skills.git',
      ref: 'main',
      repositoryPath: 'reviewer',
      revision: 'abc123',
    );
    final restored = GitSourceRecord.fromJson(record.toJson());
    expect(restored?.skillName, 'reviewer');
    expect(restored?.revision, 'abc123');
  });

  test('source metadata path stays inside the cabinet', () {
    const paths = CabinetPaths('/tmp/example-home');
    expect(p.dirname(paths.gitSourcesFile), paths.cabinetDir);
    expect(p.isAbsolute(paths.gitSourcesFile), isTrue);
  });
}
