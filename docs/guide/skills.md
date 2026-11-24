# Agent skills

FactoryBakery ships three skills: folders with a `SKILL.md` that a coding agent loads when your request matches. They are in [`skills/`](../../skills/) and are part of the installed gem.

| Skill | Ask the agent to | What it does |
| --- | --- | --- |
| [`factory-bakery-setup`](../../skills/factory-bakery-setup/SKILL.md) | "set up FactoryBakery in this project" | Adds the gem, wires RSpec or Minitest, picks a definitions directory, optional plugins and Sorbet signatures, and verifies with `factory_bakery:doctor`. |
| [`factory-bakery-migrate`](../../skills/factory-bakery-migrate/SKILL.md) | "migrate our factory_bot factories to FactoryBakery" | Works in a separate worktree, keeps the suite passing exactly as before, changes test files only by renaming factory calls, asks before simplifying definitions, and never deletes the old factories without an explicit answer. |
| [`factory-bakery-diagnostics`](../../skills/factory-bakery-diagnostics/SKILL.md) | "why won't this model bake?" | Finds the cause of a failing bake and links the matching entry of the [error catalog](../../skills/factory-bakery-diagnostics/references/diagnostics.md). |

## Install

Copy the folders to where your agent looks for skills. For Claude Code that is `.claude/skills/` in a project, or `~/.claude/skills/` for all your projects.

```sh
# one project
mkdir -p .claude/skills
cp -R "$(bundle show factory_bakery)/skills/"* .claude/skills/

# all your projects
mkdir -p ~/.claude/skills
cp -R "$(bundle show factory_bakery)/skills/"* ~/.claude/skills/
```

`bundle show factory_bakery` prints where the gem is installed. For a checkout of the repository, copy from its `skills/` directory instead.

- To follow gem updates without copying again, link each folder: `ln -s "$(bundle show factory_bakery)/skills/factory-bakery-setup" .claude/skills/`.
- Other agents read other folders (for example `.agents/skills/`). The skill format is the same, so copy or link into the folder your agent documents.
- Commit the project copy if you want your team's agents to use it, and copy again after upgrading the gem, because a copy does not update itself.

## Use

Restart or reload the agent so it picks the skills up, then ask in plain words. The migration skill is the one to read before you run it: it classifies every step as reversible or not, works in a git worktree, and stops to ask before simplifying definitions or deleting anything. See [Migrating from factory_bot](migrating-from-factory-bot.md) for the same procedure written for people.
