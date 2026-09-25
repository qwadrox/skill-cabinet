# Skill Cabinet

<p align="center">
  <img src="assets/app-icon.png" alt="Skill Cabinet logo" width="128">
</p>

**Skill Cabinet is a macOS app for organizing and sharing the skills used by your AI coding agents.**

If you use Claude Code, Codex, or another skill-based agent, Skill Cabinet gives you one place to keep your skills, group them into collections, and decide which agents should use them.

![Skill Cabinet showing collections and per-skill controls](assets/screenshots/skill-cabinet-main.png)

*Browse your skill library, organize skills into sets, and enable them for an agent with simple toggles.*

## Why use it?

AI agent skills are often scattered across several hidden folders. Skill Cabinet makes them visible and manageable:

- Keep all your skills in one library.
- Import existing skill folders that contain a `SKILL.md` file, or select skills from an HTTPS/SSH Git repository.
- Group related skills into collections such as *Writing*, *Research*, or *Development*.
- Turn collections or individual skills on and off for each agent.
- Keep agent skill folders synchronized with links managed by the cabinet.
- Track Git-imported skills, review available revisions, and update selected skills in place.
- See problems, such as missing or conflicting skills, without silently changing files you do not own.
- Back up the whole cabinet automatically to a Git history, optionally pushed to a repository you own, and restore it on a new Mac.

## How it works

The cabinet stores the original skill folders in `~/.skill-cabinet` and links enabled skills into each agent's skill directory. Your existing folders are left alone unless you explicitly import them.

## Getting started on macOS

1. Download or build **Skill Cabinet**.
2. Open the app.
3. Add the agents you use from **Manage agents**.
4. Choose **Import Skill Folder…** and select a folder containing `SKILL.md`.
5. Create a collection, add skills to it, and enable that collection for an agent.

Skill Cabinet is currently a macOS desktop app. It does not require an account or a cloud service; your library stays on your Mac unless you connect a backup repository.

## Backup

Everything in `~/.skill-cabinet` is backed up automatically: your skills, collections, agents and their assignments, and where Git-imported skills came from.

- **Local history.** The cabinet folder is a Git repository. A backup point is made about 20 seconds after each change, and only if something actually changed. Open **Backup…** (File menu or the ⋯ toolbar menu) to see the history and restore any earlier point. A restore is added as a new backup point, so it can be undone too.
- **Remote copy (optional).** In **Backup…**, connect an empty private repository, for example `git@github.com:you/skill-cabinet-backup.git`. Every backup point is then pushed there. Git signs in with your existing SSH key or saved credentials; the app stores no tokens.
- **Moving to a new Mac.** Install the app, open **Backup…**, and connect the same repository. Skill Cabinet recognizes the backup and offers to restore it, then recreates each agent's skill folder and links. Agent folders under your home folder are stored as `~/...`, so they resolve even if your user name differs.

The remote is a copy of one Mac, not a sync service. Skill Cabinet never merges or force-pushes. If the repository has changes this Mac does not have, the push stops and the Backup window explains why. Before replacing a cabinet from a remote, the previous state is kept on the local `before-restore` branch.

## Build from source

This project is built with Flutter and uses [FVM](https://fvm.app) to pin the Flutter version.

```sh
fvm flutter pub get
fvm flutter run -d macos
```

To create a release app:

```sh
fvm flutter build macos --release
```

The resulting app is at `build/macos/Build/Products/Release/Skill Cabinet.app`.

Run the test suite with:

```sh
fvm flutter test
```

## Data and privacy

Skill Cabinet stores its data locally:

```text
~/.skill-cabinet/skills/          imported skills
~/.skill-cabinet/collections.json collections and membership
~/.skill-cabinet/deployment.json  agents and assignments
~/.skill-cabinet/git_sources.json tracked Git repository sources
~/.skill-cabinet/.git/            backup history
```

The app uploads nothing unless you connect a backup repository; then it pushes the cabinet only there. It uses macOS file links to make enabled skills available to your agents.

## Status

Skill Cabinet is an early macOS release. Git repository import supports shallow HTTPS/SSH checkouts, with provider-neutral remote revision checks, cloud status indicators, and an update manager. Applying an available update remains an explicit user action.

## License

Do What The Fuck You Want To Public License (WTFPL). See [LICENSE](LICENSE).
