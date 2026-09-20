// Deployment: which skill sets and standalone skills each agent receives.
// Knows skills only by name; set membership is joined in the view layer.

import 'health.dart';

// An agent the user added.
class Agent {
  const Agent({
    required this.key,
    required this.label,
    required this.path,
    required this.dir,
    required this.custom,
    required this.enabled,
    required this.linked,
    required this.icon,
    required this.sets,
    required this.skills,
  });

  final String key;
  final String label;
  // Display form (~/...) of the agent's skill folder.
  final String path;
  // The folder as it is written in deployment.json, for editing it.
  final String dir;
  // Added by the user rather than taken from the catalog.
  final bool custom;
  final bool enabled;
  // Cabinet symlinks currently in the folder.
  final int linked;
  // Logo file in assets/agent-icons (without .png); null shows the initial.
  final String? icon;
  // Skill sets and standalone skills assigned to this agent.
  final List<String> sets;
  final List<String> skills;

  bool hasSet(String name) => sets.contains(name);
  bool hasSkill(String name) => skills.contains(name);

  Agent copyWith({List<String>? sets, List<String>? skills}) => Agent(
    key: key,
    label: label,
    path: path,
    dir: dir,
    custom: custom,
    enabled: enabled,
    linked: linked,
    icon: icon,
    sets: sets ?? this.sets,
    skills: skills ?? this.skills,
  );
}

// An agent from the catalog that has not been added yet.
class CatalogAgent {
  const CatalogAgent({
    required this.key,
    required this.label,
    required this.path,
    required this.icon,
    required this.installed,
  });

  final String key;
  final String label;
  final String path;
  final String? icon;
  // Its config folder exists on this machine.
  final bool installed;
}

// A real skill folder inside an agent's directory that the cabinet does
// not own yet — offered for import into the Library.
class ForeignSkill {
  const ForeignSkill({required this.name, required this.agent, required this.path});

  final String name;
  // Label of the agent whose folder holds it.
  final String agent;
  final String path;
}

class DeploymentSnapshot {
  const DeploymentSnapshot({
    required this.agents,
    required this.catalog,
    required this.foreign,
    this.issues = const [],
    this.notice = '',
  });

  static const empty = DeploymentSnapshot(agents: [], catalog: [], foreign: []);

  // The added agents, in the order they were added.
  final List<Agent> agents;
  final List<CatalogAgent> catalog;
  final List<ForeignSkill> foreign;
  // What reconciliation could not carry out, reported but never forced.
  final List<HealthIssue> issues;
  final String notice;

  Agent? agent(String key) {
    for (final a in agents) {
      if (a.key == key) return a;
    }
    return null;
  }

  // Optimistic local edits; the service's snapshot overwrites them.
  DeploymentSnapshot withAgentSkill(String key, String skill, bool enabled) =>
      _withAgent(key, (a) => a.copyWith(skills: [...a.skills.where((s) => s != skill), if (enabled) skill]));

  DeploymentSnapshot withAgentSet(String key, String set, bool enabled) =>
      _withAgent(key, (a) => a.copyWith(sets: [...a.sets.where((s) => s != set), if (enabled) set]));

  DeploymentSnapshot _withAgent(String key, Agent Function(Agent) edit) => DeploymentSnapshot(
    agents: [for (final a in agents) a.key == key ? edit(a) : a],
    catalog: catalog,
    foreign: foreign,
    issues: issues,
    notice: notice,
  );
}
