import 'dart:isolate';

import '../domain/collections.dart';
import '../domain/deployment.dart';
import '../domain/git_import.dart';
import '../domain/library.dart';
import '../services/cabinet_paths.dart';
import '../services/collections_service.dart';
import '../services/deployment_service.dart';
import '../services/library_service.dart';
import '../services/git_import_service.dart';

// The services, run off the UI isolate. Holds nothing but the paths, so
// every closure below is cheap to send. Calls are serialized: each
// operation reads a state file, edits and rewrites it, so two in flight
// could lose an edit.
class CabinetBackend {
  CabinetBackend(this.paths);

  final CabinetPaths paths;
  Future<void> _tail = Future.value();

  LibraryService get _library => LibraryService(paths);
  GitImportService get _git => GitImportService(paths);
  CollectionsService get _collections => CollectionsService(paths);
  DeploymentService get _deployment => DeploymentService(paths);

  Future<T> _run<T>(T Function() op) {
    final result = _tail.then((_) => Isolate.run(op));
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<T> _runAsync<T>(Future<T> Function() op) {
    final result = _tail.then((_) => Isolate.run(op));
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Library
  Future<LibrarySnapshot> scan() {
    final s = _library;
    return _run(s.scan);
  }

  Future<ImportScan> scanForImport(List<String> paths) {
    final s = _library;
    return _run(() => s.scanForImport(paths));
  }

  Future<LibraryImportResult> importSkills(List<String> paths, {required bool move}) {
    final s = _library;
    return _run(() => s.importSkills(paths, move: move));
  }

  Future<GitImportPreview> previewGit(String url) {
    final service = _git;
    return _runAsync(() => service.preview(url));
  }

  Future<GitImportResult> importGit(GitImportPreview preview, List<String> paths) {
    final service = _git;
    return _run(() => service.importSelected(preview, paths));
  }

  Future<void> discardGitPreview(GitImportPreview preview) {
    final service = _git;
    return _run(() => service.discard(preview));
  }

  Future<void> removeGitSource(String skillName) {
    final service = _git;
    return _run(() => service.removeSource(skillName));
  }

  Future<Map<String, GitSourceRecord>> gitSources() {
    final service = _git;
    return _run(service.sources);
  }

  Future<GitUpdateCheckResult> checkGitUpdates({bool force = false}) {
    final service = _git;
    return _runAsync(() => service.checkForUpdates(force: force));
  }

  Future<LibraryDeleteResult> deleteSkill(String name) {
    final s = _library;
    return _run(() => s.deleteSkill(name));
  }

  Future<SkillPreview> preview(String name) {
    final s = _library;
    return _run(() => s.preview(name));
  }

  // Collections
  Future<CollectionsSnapshot> listSets() {
    final s = _collections;
    return _run(s.list);
  }

  Future<CollectionsSnapshot> createSet(String name) {
    final s = _collections;
    return _run(() => s.createSet(name));
  }

  Future<CollectionsSnapshot> deleteSet(String name) {
    final s = _collections;
    return _run(() => s.deleteSet(name));
  }

  Future<CollectionsSnapshot> setMembership(String set, String skill, {required bool member}) {
    final s = _collections;
    return _run(() => s.setMembership(set, skill, member: member));
  }

  Future<CollectionsSnapshot> dropSkill(String skill) {
    final s = _collections;
    return _run(() => s.dropSkill(skill));
  }

  // Deployment
  Future<DeploymentSnapshot> sync() {
    final s = _deployment;
    return _run(s.sync);
  }

  Future<DeploymentSnapshot> setAgentSet(String agent, String set, {required bool enabled}) {
    final s = _deployment;
    return _run(() => s.setAgentSet(agent, set, enabled: enabled));
  }

  Future<DeploymentSnapshot> setAgentSkill(String agent, String skill, {required bool enabled}) {
    final s = _deployment;
    return _run(() => s.setAgentSkill(agent, skill, enabled: enabled));
  }

  Future<DeploymentSnapshot> setAgentEnabled(String key, {required bool enabled}) {
    final s = _deployment;
    return _run(() => s.setAgentEnabled(key, enabled: enabled));
  }

  Future<DeploymentSnapshot> unassignSkill(String skill) {
    final s = _deployment;
    return _run(() => s.unassignSkill(skill));
  }

  Future<DeploymentSnapshot> addAgent(String key) {
    final s = _deployment;
    return _run(() => s.addAgent(key));
  }

  Future<DeploymentSnapshot> addCustomAgent(String label, String dir) {
    final s = _deployment;
    return _run(() => s.addCustomAgent(label, dir));
  }

  Future<DeploymentSnapshot> setAgentPath(String key, String dir) {
    final s = _deployment;
    return _run(() => s.setAgentPath(key, dir));
  }

  Future<DeploymentSnapshot> removeAgent(String key) {
    final s = _deployment;
    return _run(() => s.removeAgent(key));
  }
}
