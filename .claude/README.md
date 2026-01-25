# Claude Code Configuration for Async

This directory contains shared Claude Code configuration for the Async project.

## MCP Servers

See `mcp-configs/async-servers.json` for recommended MCP servers:

- **github**: Read/write GitHub issues, PRs, repos - core for our GitHub integration feature
- **supabase**: Database operations - if we choose Supabase as backend
- **memory**: Persistent memory across sessions - useful for agent context

### Setup

1. Copy the servers you need to your `~/.claude.json`:
   ```json
   {
     "mcpServers": {
       "github": { ... }
     }
   }
   ```

2. Replace placeholder values:
   - `YOUR_GITHUB_PAT_HERE` - Create at https://github.com/settings/tokens (needs `repo` scope)
   - `YOUR_PROJECT_REF` - From your Supabase dashboard URL

## Agents

Specialized subagents in `agents/`:

- **architect.md** - System design and architecture decisions
- **planner.md** - Task breakdown and planning
- **code-reviewer.md** - Code review and quality checks

These are from [everything-claude-code](https://github.com/affaan-m/everything-claude-code).

## Project Settings

`settings.json` contains shared Claude Code settings:
- Swift LSP enabled
- Common bash permissions for Swift/Xcode development

## Plugin

The `everything-claude-code` plugin is recommended. Install via:
```
/plugin marketplace add affaan-m/everything-claude-code
/plugin install everything-claude-code@everything-claude-code
```

Or add to your `~/.claude/settings.json`:
```json
{
  "extraKnownMarketplaces": {
    "everything-claude-code": {
      "source": {
        "source": "github",
        "repo": "affaan-m/everything-claude-code"
      }
    }
  },
  "enabledPlugins": {
    "everything-claude-code@everything-claude-code": true
  }
}
```
