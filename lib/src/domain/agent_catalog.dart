// Every agent that can be added. Adapted from skills-manager's
// tool_adapters.rs. `dir` (relative to \$HOME) receives the links; `detect`
// existing means the agent is installed. `icon` names a logo in
// assets/agent-icons (see tool/make_agent_icons.swift); null shows the
// agent's initial instead.

class AgentDefinition {
  const AgentDefinition({required this.key, required this.label, required this.dir, required this.detect, this.icon});

  final String key;
  final String label;
  final String dir;
  final String detect;
  final String? icon;
}

const agentCatalog = <AgentDefinition>[
  AgentDefinition(key: 'adal', label: 'AdaL', dir: '.adal/skills', detect: '.adal', icon: 'adal'),
  AgentDefinition(key: 'amp', label: 'Amp', dir: '.config/agents/skills', detect: '.config/agents', icon: 'amp'),
  AgentDefinition(
    key: 'antigravity',
    label: 'Antigravity',
    dir: '.gemini/antigravity/skills',
    detect: '.gemini/antigravity',
    icon: 'antigravity',
  ),
  AgentDefinition(key: 'augment', label: 'Augment', dir: '.augment/skills', detect: '.augment', icon: 'augment'),
  AgentDefinition(key: 'autoclaw', label: 'AutoClaw', dir: '.openclaw-autoclaw/skills', detect: '.openclaw-autoclaw'),
  AgentDefinition(key: 'claude', label: 'Claude Code', dir: '.claude/skills', detect: '.claude', icon: 'claude-code'),
  AgentDefinition(key: 'cline', label: 'Cline', dir: '.agents/skills', detect: '.cline', icon: 'cline'),
  AgentDefinition(
    key: 'codebuddy',
    label: 'CodeBuddy',
    dir: '.codebuddy/skills',
    detect: '.codebuddy',
    icon: 'codebuddy',
  ),
  AgentDefinition(key: 'codex', label: 'Codex', dir: '.codex/skills', detect: '.codex', icon: 'codex'),
  AgentDefinition(
    key: 'command_code',
    label: 'Command Code',
    dir: '.commandcode/skills',
    detect: '.commandcode',
    icon: 'commandcode',
  ),
  AgentDefinition(key: 'continue', label: 'Continue', dir: '.continue/skills', detect: '.continue', icon: 'continue'),
  AgentDefinition(
    key: 'cortex',
    label: 'Cortex Code',
    dir: '.snowflake/cortex/skills',
    detect: '.snowflake/cortex',
    icon: 'cortex',
  ),
  AgentDefinition(key: 'crush', label: 'Crush', dir: '.config/crush/skills', detect: '.config/crush', icon: 'crush'),
  AgentDefinition(key: 'cursor', label: 'Cursor', dir: '.cursor/skills', detect: '.cursor', icon: 'cursor'),
  AgentDefinition(
    key: 'deepagents',
    label: 'Deep Agents',
    dir: '.deepagents/agent/skills',
    detect: '.deepagents',
    icon: 'deepagents',
  ),
  AgentDefinition(
    key: 'deepseek_harness',
    label: 'DeepSeek Harness',
    dir: '.dsh/skills',
    detect: '.dsh',
    icon: 'deepseek-harness',
  ),
  AgentDefinition(key: 'droid', label: 'Droid', dir: '.factory/skills', detect: '.factory', icon: 'droid'),
  AgentDefinition(key: 'easyclaw', label: 'EasyClaw', dir: '.easyclaw/skills', detect: '.easyclaw'),
  AgentDefinition(
    key: 'firebender',
    label: 'Firebender',
    dir: '.firebender/skills',
    detect: '.firebender',
    icon: 'firebender',
  ),
  AgentDefinition(key: 'gemini_cli', label: 'Gemini CLI', dir: '.gemini/skills', detect: '.gemini', icon: 'gemini_cli'),
  AgentDefinition(
    key: 'github_copilot',
    label: 'GitHub Copilot',
    dir: '.copilot/skills',
    detect: '.copilot',
    icon: 'github_copilot',
  ),
  AgentDefinition(
    key: 'gitlab_duo',
    label: 'GitLab Duo',
    dir: '.gitlab/duo/skills',
    detect: '.gitlab/duo',
    icon: 'gitlab_duo',
  ),
  AgentDefinition(key: 'goose', label: 'Goose', dir: '.config/goose/skills', detect: '.config/goose', icon: 'goose'),
  AgentDefinition(key: 'grok', label: 'Grok', dir: '.grok/skills', detect: '.grok', icon: 'grok'),
  AgentDefinition(key: 'hermes', label: 'Hermes Agent', dir: '.hermes/skills', detect: '.hermes', icon: 'hermes'),
  AgentDefinition(key: 'bob', label: 'IBM Bob', dir: '.bob/skills', detect: '.bob', icon: 'ibm_bob'),
  AgentDefinition(key: 'iflow', label: 'iFlow CLI', dir: '.iflow/skills', detect: '.iflow', icon: 'iflow'),
  AgentDefinition(key: 'junie', label: 'Junie', dir: '.junie/skills', detect: '.junie', icon: 'junie'),
  AgentDefinition(
    key: 'kilo_code',
    label: 'Kilo Code',
    dir: '.kilocode/skills',
    detect: '.kilocode',
    icon: 'kilo-code',
  ),
  AgentDefinition(key: 'kimi', label: 'Kimi Code CLI', dir: '.kimi-code/skills', detect: '.kimi-code', icon: 'kimi'),
  AgentDefinition(key: 'kiro', label: 'Kiro CLI', dir: '.kiro/skills', detect: '.kiro', icon: 'kiro'),
  AgentDefinition(key: 'kode', label: 'Kode', dir: '.kode/skills', detect: '.kode'),
  AgentDefinition(key: 'mcpjam', label: 'MCPJam', dir: '.mcpjam/skills', detect: '.mcpjam', icon: 'mcpjam'),
  AgentDefinition(
    key: 'mistral_vibe',
    label: 'Mistral Vibe',
    dir: '.vibe/skills',
    detect: '.vibe',
    icon: 'mistral_vibe',
  ),
  AgentDefinition(key: 'mux', label: 'Mux', dir: '.mux/skills', detect: '.mux'),
  AgentDefinition(key: 'neovate', label: 'Neovate', dir: '.neovate/skills', detect: '.neovate', icon: 'neovate'),
  AgentDefinition(key: 'omp_agent', label: 'OMP Agent', dir: '.omp/agent/skills', detect: '.omp/agent'),
  AgentDefinition(key: 'openclaw', label: 'OpenClaw', dir: '.openclaw/skills', detect: '.openclaw', icon: 'openclaw'),
  AgentDefinition(
    key: 'opencode',
    label: 'OpenCode',
    dir: '.config/opencode/skills',
    detect: '.config/opencode',
    icon: 'opencode',
  ),
  AgentDefinition(
    key: 'openhands',
    label: 'OpenHands',
    dir: '.openhands/skills',
    detect: '.openhands',
    icon: 'openhands',
  ),
  AgentDefinition(key: 'pi', label: 'Pi', dir: '.pi/agent/skills', detect: '.pi/agent', icon: 'pi'),
  AgentDefinition(key: 'pochi', label: 'Pochi', dir: '.pochi/skills', detect: '.pochi', icon: 'pochi'),
  AgentDefinition(key: 'qclaw', label: 'QClaw', dir: '.qclaw/skills', detect: '.qclaw'),
  AgentDefinition(key: 'qoder', label: 'Qoder', dir: '.qoder/skills', detect: '.qoder', icon: 'qoder'),
  AgentDefinition(key: 'qwen_code', label: 'Qwen Code', dir: '.qwen/skills', detect: '.qwen', icon: 'qwen_code'),
  AgentDefinition(key: 'replit', label: 'Replit', dir: '.config/agents/skills', detect: '.replit', icon: 'replit'),
  AgentDefinition(key: 'roo_code', label: 'Roo Code', dir: '.roo/skills', detect: '.roo', icon: 'roo_code'),
  AgentDefinition(key: 'trae_cn', label: 'TRAE CN', dir: '.trae-cn/skills', detect: '.trae-cn', icon: 'trae-cn'),
  AgentDefinition(key: 'trae', label: 'TRAE IDE', dir: '.trae/skills', detect: '.trae', icon: 'trae'),
  AgentDefinition(key: 'warp', label: 'Warp', dir: '.agents/skills', detect: '.warp', icon: 'warp'),
  AgentDefinition(
    key: 'windsurf',
    label: 'Windsurf',
    dir: '.codeium/windsurf/skills',
    detect: '.codeium/windsurf',
    icon: 'windsurf',
  ),
  AgentDefinition(
    key: 'workbuddy',
    label: 'WorkBuddy',
    dir: '.workbuddy/skills',
    detect: '.workbuddy',
    icon: 'workbuddy',
  ),
  AgentDefinition(key: 'zcode', label: 'ZCode', dir: '.zcode/skills', detect: '.zcode', icon: 'zcode'),
  AgentDefinition(key: 'zencoder', label: 'Zencoder', dir: '.zencoder/skills', detect: '.zencoder', icon: 'zencoder'),
];

AgentDefinition? catalogEntry(String key) {
  for (final agent in agentCatalog) {
    if (agent.key == key) return agent;
  }
  return null;
}
