# Using Agent Skills

This guide explains how to use GitHub Copilot Agent Skills in this Flutter Android template project.

## What Are Agent Skills?

Agent Skills are specialized, reusable workflows that guide GitHub Copilot to perform specific tasks. They're automatically discovered by Copilot in VS Code, GitHub CLI, and GitHub.com.

**Location**: `.github/skills/`

## Available Skills

### 🎨 icon-generation

Generate app icons and launcher icons for your Flutter Android app.

**Use when**:
- Creating UI icons
- Generating launcher icons
- Setting up flutter_launcher_icons package

**Example prompts**:
```
@workspace Use the icon-generation skill to create a launcher icon for my fitness tracking app. Primary color: #FF6B6B

Use icon-generation to generate a search icon SVG for the app toolbar
```

---

### 🐛 android-debug

Debug Android-specific issues including crashes, device connection, and performance problems.

**Use when**:
- App crashes or runtime errors
- Device/emulator connection issues
- Performance problems (lag, memory)
- Platform channel issues

**Example prompts**:
```
@workspace My app crashes on startup. Use android-debug to help me diagnose this.

@workspace The app is laggy when scrolling. Use android-debug skill to profile performance.

Use android-debug to help me connect to my Android device over USB
```

---

### 🔧 ci-debug

Debug GitHub Actions workflow failures and CI-specific issues.

**Use when**:
- GitHub Actions workflows fail
- CI build errors (but builds work locally)
- Test failures only in CI
- Artifact or deployment issues

**Example prompts**:
```
@workspace The build.yml workflow is failing. Use ci-debug skill to diagnose.

@workspace Tests pass locally but fail in CI. Use ci-debug to investigate.

Use ci-debug skill to help me understand why the release workflow isn't creating artifacts
```

---

### 🏗️ build-fix

Diagnose and fix Flutter build failures.

**Use when**:
- `flutter build apk` fails
- Gradle errors
- Dependency conflicts
- Compilation errors

**Example prompts**:
```
@workspace My Flutter build is failing with a Gradle error. Use build-fix skill.

@workspace I'm getting dependency conflicts. Use build-fix to resolve them.

Use build-fix skill to help me troubleshoot this R8 shrinking error
```

## How to Use Skills

### In VS Code

Skills are automatically available in Copilot Chat. Use `@workspace` to give Copilot context:

```
@workspace Use the [skill-name] skill to [describe your task]
```

### In GitHub CLI

If using `gh copilot`, skills are automatically available:

```bash
gh copilot suggest "Use android-debug to help me fix this crash"
```

### Best Practices

1. **Be specific**: Mention the skill name explicitly
2. **Provide context**: Include error messages, logs, or descriptions
3. **Use @workspace**: This gives Copilot access to your codebase
4. **Follow the workflow**: Skills provide step-by-step guidance - follow them sequentially

### Examples

#### Example 1: Creating an App Icon

```
@workspace Use the icon-generation skill to create a launcher icon for my weather app.

Requirements:
- Style: minimal, flat design
- Primary color: #4A90E2
- Symbol: sun with clouds
- Transparent background

Provide the 1024x1024 source image and flutter_launcher_icons setup instructions.
```

#### Example 2: Debugging a Crash

```
@workspace My app crashes with this error:

[Error log here]

Use the android-debug skill to help me diagnose and fix this issue.
```

#### Example 3: Fixing Build Failures

```
@workspace flutter build apk is failing with this Gradle error:

[Error message here]

Use the build-fix skill to help me resolve this.
```

#### Example 4: Debugging CI Failures

```
@workspace The build.yml workflow is failing at the "Build APK" step. Use the ci-debug skill to investigate.

Workflow run: [link or run ID]
```

## Skill Structure

Each skill follows this format:

```markdown
---
name: skill-name
description: What the skill does and when to use it
---

# Skill Title

## When to Use This Skill
[Clear criteria for when to invoke this skill]

## Workflow
[Step-by-step instructions]

## Common Issues
[Known problems and solutions]

## Examples
[Practical examples]

## Resources
[Links to documentation]
```

## Creating Custom Skills

Want to add your own skills? See `.github/skills/README.md` for guidelines.

Key requirements:
1. Create a folder: `.github/skills/your-skill-name/`
2. Create `SKILL.md` with YAML frontmatter
3. Include clear "When to Use" section
4. Provide structured workflow or instructions
5. Add practical examples

## Verifying Skills

Run the verification script to ensure skills are properly formatted:

```bash
./.github/skills/verify-skills.sh
```

This checks:
- YAML frontmatter presence and format
- Required fields (name, description)
- File content and structure

## Troubleshooting

### Skills not appearing in Copilot

1. **Check VS Code extension**: Ensure GitHub Copilot extension is updated
2. **Restart VS Code**: Skills are loaded on startup
3. **Verify format**: Run `.github/skills/verify-skills.sh`
4. **Check location**: Skills must be in `.github/skills/*/SKILL.md`

### Skill not working as expected

1. **Be explicit**: Mention the skill name in your prompt
2. **Provide context**: Use `@workspace` and include relevant information
3. **Follow the workflow**: Skills provide step-by-step guidance
4. **Check the skill content**: Read `.github/skills/[skill-name]/SKILL.md` directly

## Additional Resources

- **Official Documentation**: [GitHub Agent Skills Docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)
- **Skills Directory**: `.github/skills/` - Browse all available skills
- **Agent Documentation**: `AGENTS.md` - Learn about Copilot agents
- **Skills README**: `.github/skills/README.md` - Complete skills documentation

## Feedback

Found an issue with a skill or have a suggestion? Open an issue or PR with the `skill` label.
