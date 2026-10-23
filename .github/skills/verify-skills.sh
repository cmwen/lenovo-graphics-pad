#!/bin/bash
# Verify Agent Skills Structure
# Checks that all skills follow the proper format and OpenCode symlinks exist

set -e

SKILLS_DIR=".github/skills"
OPENCODE_DIR=".opencode/skills"
ERRORS=0

echo "🔍 Verifying Agent Skills..."
echo

# Check if skills directory exists
if [ ! -d "$SKILLS_DIR" ]; then
    echo "❌ Skills directory not found: $SKILLS_DIR"
    exit 1
fi

# Find all SKILL.md files
SKILL_FILES=$(find "$SKILLS_DIR" -name "SKILL.md" -type f)

if [ -z "$SKILL_FILES" ]; then
    echo "❌ No SKILL.md files found"
    exit 1
fi

# Check each skill file
for skill_file in $SKILL_FILES; do
    skill_name=$(basename $(dirname "$skill_file"))
    echo "📋 Checking skill: $skill_name"
    
    # Check if file starts with YAML frontmatter
    if ! head -1 "$skill_file" | grep -q "^---$"; then
        echo "   ❌ Missing YAML frontmatter opening delimiter"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    # Check for required frontmatter fields
    frontmatter=$(awk '/^---$/{flag=!flag; next} flag' "$skill_file" | head -20)
    
    if ! echo "$frontmatter" | grep -q "^name:"; then
        echo "   ❌ Missing 'name' field in frontmatter"
        ERRORS=$((ERRORS + 1))
    else
        echo "   ✓ Has 'name' field"
    fi
    
    if ! echo "$frontmatter" | grep -q "^description:"; then
        echo "   ❌ Missing 'description' field in frontmatter"
        ERRORS=$((ERRORS + 1))
    else
        echo "   ✓ Has 'description' field"
    fi
    
    # Check file size (should have content beyond frontmatter)
    file_size=$(wc -l < "$skill_file")
    if [ "$file_size" -lt 10 ]; then
        echo "   ⚠️  File seems too short ($file_size lines)"
    else
        echo "   ✓ Has content ($file_size lines)"
    fi

    # Check OpenCode symlink exists
    if [ -L "$OPENCODE_DIR/$skill_name" ]; then
        echo "   ✓ OpenCode symlink exists"
    elif [ -d "$OPENCODE_DIR" ]; then
        echo "   ⚠️  Missing OpenCode symlink at $OPENCODE_DIR/$skill_name"
    fi
    
    echo
done

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All skills verified successfully!"
    echo "Found $(echo "$SKILL_FILES" | wc -l) skill(s)"
else
    echo "❌ Found $ERRORS error(s)"
    exit 1
fi
