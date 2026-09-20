// The app's core: one slice per bounded context (each a copy of its
// service's last snapshot), the view state, and one method per user
// intent. This is the only place contexts meet: when an intent spans them
// (a reclaimed foreign skill is relinked for its agent; a deleted skill
// leaves every set and agent), the controller reads one slice and commands another
// service. Services never call each other.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../domain/collections.dart';
import '../domain/deployment.dart';
import '../domain/git_import.dart';
import '../domain/library.dart';
import '../services/cabinet_paths.dart';
import 'backend.dart';

class CabinetController extends ChangeNotifier {
  CabinetController(CabinetPaths paths) : _backend = CabinetBackend(paths) {
    // Every edit of the field is a change of the filter, however it was
    // made: typed, cleared with the ⓧ, or dropped by a view change.
    searchField.addListener(notifyListeners);
  }

  @override
  void dispose() {
    searchField.removeListener(notifyListeners);
    searchField.dispose();
    super.dispose();
  }

  final CabinetBackend _backend;

  LibrarySnapshot library = LibrarySnapshot.empty;
  CollectionsSnapshot collections = CollectionsSnapshot.empty;
  DeploymentSnapshot deployment = DeploymentSnapshot.empty;
  bool loaded = false;

  // The selected skill set, by name; null = all skills.
  String? _selectedSet;
  // The agent whose assignments the switches edit, by key.
  String? _selectedAgent;
  // The search field's own controller: the query has one home, so an
  // empty field and an empty filter cannot drift apart.
  final TextEditingController searchField = TextEditingController();
  // The "add to set" list narrowed to the skills that are in no skill
  // set at all, for finding what has not been filed anywhere yet.
  bool looseOnly = false;
  // Skill sets opened in the sectioned "All skills" view.
  final Set<String> expandedSets = {};
  // The skill whose SKILL.md is shown beside the list, and its contents
  // once read (null while loading, never another skill's).
  String? previewName;
  SkillPreview? preview;
  String notice = '';

  String get search => searchField.text;

  SkillSet? get selectedSet => _selectedSet == null ? null : collections.named(_selectedSet!);

  Agent? get selectedAgent {
    final agents = deployment.agents;
    if (agents.isEmpty) return null;
    return deployment.agent(_selectedAgent ?? '') ?? agents.first;
  }

  // ---- loading ----------------------------------------------------------------

  Future<void> load() async {
    try {
      await Future.wait([
        _backend.scan().then(_libraryLoaded),
        _backend.listSets().then(_collectionsLoaded),
        _backend.sync().then(_deploymentLoaded),
        if (previewName != null) _backend.preview(previewName!).then(_previewLoaded),
      ]);
    } catch (e) {
      _failed(e);
    }
    loaded = true;
    notifyListeners();
  }

  // Re-reads everything, the previewed SKILL.md included (it may have
  // been edited outside the app).
  Future<void> refresh() {
    _clearNotice();
    return load();
  }

  void _libraryLoaded(LibrarySnapshot snapshot) {
    library = snapshot;
    // The previewed skill left the store: close the preview.
    if (previewName != null && !snapshot.has(previewName!)) {
      previewName = null;
      preview = null;
    }
    _noticed(snapshot.notice);
    notifyListeners();
  }

  void _collectionsLoaded(CollectionsSnapshot snapshot) {
    collections = snapshot;
    if (_selectedSet != null && snapshot.named(_selectedSet!) == null) _selectedSet = null;
    expandedSets.retainWhere((name) => snapshot.named(name) != null);
    _noticed(snapshot.notice);
    notifyListeners();
  }

  void _deploymentLoaded(DeploymentSnapshot snapshot) {
    // Removing the selected agent selects the one that takes its place.
    final before = deployment.agents.indexWhere((a) => a.key == _selectedAgent);
    deployment = snapshot;
    if (snapshot.agent(_selectedAgent ?? '') == null) {
      final agents = snapshot.agents;
      _selectedAgent = agents.isEmpty ? null : agents[before.clamp(0, agents.length - 1)].key;
    }
    _noticed(snapshot.notice);
    notifyListeners();
  }

  void _previewLoaded(SkillPreview result) {
    // A result for anything but the current selection is stale.
    if (result.name != previewName) return;
    preview = result;
    notifyListeners();
  }

  void _failed(Object error) {
    notice = 'Error: $error';
    notifyListeners();
  }

  // A result's notice replaces the current one only when it says something,
  // so the other contexts' empty notices don't wipe it.
  void _noticed(String text) {
    if (text.isNotEmpty) notice = text;
  }

  // A user intent that reaches a service clears the previous notice.
  void _clearNotice() {
    notice = '';
    notifyListeners();
  }

  void dismissNotice() => _clearNotice();

  // ---- view state -------------------------------------------------------------

  // Changing the view drops the search with it: a query belongs to the
  // list it was typed over, and a filter the user cannot see is the one
  // thing worse than no filter.
  void selectAll() {
    _selectedSet = null;
    _clearQueries();
    notifyListeners();
  }

  void selectSet(String name) {
    _selectedSet = name;
    _clearQueries();
    notifyListeners();
  }

  void selectAgent(String key) {
    _selectedAgent = key;
    notifyListeners();
  }

  // Changing the view drops the query and the filter with it: both
  // belong to the list they were set over.
  void _clearQueries() {
    looseOnly = false;
    if (searchField.text.isNotEmpty) searchField.clear();
  }

  void toggleLooseOnly() {
    looseOnly = !looseOnly;
    notifyListeners();
  }

  void toggleSection(String set) {
    if (!expandedSets.remove(set)) expandedSets.add(set);
    notifyListeners();
  }

  // Pressing the previewed skill again closes the preview.
  void togglePreview(String name) {
    if (previewName == name) return closePreview();
    previewName = name;
    preview = null;
    notifyListeners();
    _backend.preview(name).then(_previewLoaded, onError: _failed);
  }

  void closePreview() {
    previewName = null;
    preview = null;
    notifyListeners();
  }

  // ---- library ----------------------------------------------------------------

  // Folders dropped on the window or picked in the open panel are
  // searched for skills; the user then chooses which of them to take, and
  // whether to copy or move. Nothing is written by this call.
  Future<ImportScan> scanForImport(Iterable<String> paths) async {
    _clearNotice();
    try {
      final scan = await _backend.scanForImport(paths.toList());
      if (scan.notice.isNotEmpty) {
        notice = scan.notice;
        notifyListeners();
      }
      return scan;
    } catch (e) {
      _failed(e);
      return ImportScan.empty;
    }
  }

  // Copies (or moves, leaving nothing behind) chosen skill folders into
  // the store. An import lands in the library and nowhere else: which
  // agents get it is always a separate, explicit choice in the UI.
  Future<void> importSkills(Iterable<String> paths, {required bool move}) {
    _clearNotice();
    return _imported(_backend.importSkills(paths.toList(), move: move));
  }

  // A skill found in an agent's folder is moved into the store, which takes
  // it out of that folder; it is relinked when the user enables it, like any
  // other skill in the library.
  Future<void> importForeign(ForeignSkill skill) => importSkills([skill.path], move: true);

  Future<GitImportPreview?> previewGit(String url) async {
    _clearNotice();
    notice = 'Cloning repository…';
    notifyListeners();
    try {
      final preview = await _backend.previewGit(url);
      if (preview.isEmpty) {
        await _backend.discardGitPreview(preview);
        notice = 'No skill folder (a folder with a SKILL.md) found in that Git repository';
        notifyListeners();
      } else {
        _clearNotice();
      }
      return preview;
    } catch (e) {
      _failed(e);
      return null;
    }
  }

  Future<void> importGit(GitImportPreview preview, Iterable<String> paths) async {
    _clearNotice();
    try {
      final result = await _backend.importGit(preview, paths.toList());
      _libraryLoaded(result.library.snapshot);
    } catch (e) {
      _failed(e);
    }
  }

  Future<void> discardGitPreview(GitImportPreview preview) async {
    try {
      await _backend.discardGitPreview(preview);
    } catch (_) {
      // The checkout lives under the system temp directory and is harmless if
      // it was already removed or the OS cleans it up later.
    }
  }

  Future<void> _imported(Future<LibraryImportResult> pending) async {
    try {
      _libraryLoaded((await pending).snapshot);
    } catch (e) {
      _failed(e);
    }
  }

  Future<void> deleteSkill(String name) async {
    _clearNotice();
    try {
      final result = await _backend.deleteSkill(name);
      _libraryLoaded(result.snapshot);
      final deleted = result.deleted;
      if (deleted == null) return;
      try {
        await _backend.removeGitSource(deleted);
      } catch (e) {
        _noticed('Skill deleted, but Git tracking could not be cleared: $e');
      }
      // The folder is gone: drop the name from every skill set and agent,
      // which also removes its now-dangling agent links.
      await Future.wait([
        _backend.dropSkill(deleted).then(_collectionsLoaded),
        _backend.unassignSkill(deleted).then(_deploymentLoaded),
      ]);
    } catch (e) {
      _failed(e);
    }
  }

  // Finder and the default editor. The store folder itself is opened, not
  // just selected in its parent.
  Future<void> openStore() async {
    await Directory(library.rootPath).create(recursive: true);
    await _open([library.rootPath]);
  }

  Future<void> revealSkill(String name) => _open(['-R', p.join(library.rootPath, name, 'SKILL.md')]);

  Future<void> openSkillFile(String name) => _open([p.join(library.rootPath, name, 'SKILL.md')]);

  Future<void> revealPath(String path) => _open(['-R', path]);

  // Links in a previewed SKILL.md.
  Future<void> openUrl(String url) => _open([url]);

  Future<void> _open(List<String> args) async {
    final result = await Process.run('/usr/bin/open', args);
    if (result.exitCode != 0) _failed('could not open ${args.last}: ${result.stderr}'.trim());
  }

  // ---- collections ------------------------------------------------------------

  // Creates a set and shows it.
  Future<void> createSet(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) return;
    _clearNotice();
    _selectedSet = name;
    await _backend.createSet(name).then(_collectionsLoaded, onError: _failed);
  }

  Future<void> deleteSet(String name) async {
    _clearNotice();
    if (_selectedSet == name) _selectedSet = null;
    await _backend.deleteSet(name).then(_collectionsLoaded, onError: _failed);
  }

  Future<void> setMembership(String set, String skill, {required bool member}) async {
    _clearNotice();
    await _backend.setMembership(set, skill, member: member).then(_collectionsLoaded, onError: _failed);
  }

  // ---- deployment -------------------------------------------------------------

  // A skill's own switch for the selected agent. Locked while an assigned
  // set holds the skill (the view disables it).
  Future<void> setSkillEnabled(String skill, bool enabled) async {
    final agent = selectedAgent;
    if (agent == null) return;
    deployment = deployment.withAgentSkill(agent.key, skill, enabled);
    _clearNotice();
    await _backend.setAgentSkill(agent.key, skill, enabled: enabled).then(_deploymentLoaded, onError: _failed);
  }

  // Skill sets are atomic: assigned or not, as a whole, per agent.
  Future<void> setSetEnabled(String set, bool enabled) async {
    final agent = selectedAgent;
    if (agent == null) return;
    deployment = deployment.withAgentSet(agent.key, set, enabled);
    _clearNotice();
    await _backend.setAgentSet(agent.key, set, enabled: enabled).then(_deploymentLoaded, onError: _failed);
  }

  Future<void> setAgentEnabled(String key, bool enabled) async {
    _clearNotice();
    await _backend.setAgentEnabled(key, enabled: enabled).then(_deploymentLoaded, onError: _failed);
  }

  // A newly added agent becomes the selected one.
  Future<void> addAgent(String key) async {
    _clearNotice();
    try {
      final snapshot = await _backend.addAgent(key);
      if (snapshot.agent(key) != null) _selectedAgent = key;
      _deploymentLoaded(snapshot);
    } catch (e) {
      _failed(e);
    }
  }

  // Same, for an agent the catalog does not know.
  Future<void> addCustomAgent(String label, String dir) async {
    _clearNotice();
    try {
      final before = {for (final a in deployment.agents) a.key};
      final snapshot = await _backend.addCustomAgent(label, dir);
      final added = snapshot.agents.where((a) => !before.contains(a.key)).toList();
      if (added.isNotEmpty) _selectedAgent = added.last.key;
      _deploymentLoaded(snapshot);
    } catch (e) {
      _failed(e);
    }
  }

  Future<void> setAgentPath(String key, String dir) async {
    _clearNotice();
    await _backend.setAgentPath(key, dir).then(_deploymentLoaded, onError: _failed);
  }

  Future<void> removeAgent(String key) async {
    _clearNotice();
    await _backend.removeAgent(key).then(_deploymentLoaded, onError: _failed);
  }
}
