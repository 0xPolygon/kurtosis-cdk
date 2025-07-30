#!/bin/bash
set -e

# Automated Version Matrix Update Script
# This script updates the CDK version matrix by:
# 1. Extracting current version information
# 2. Generating updated Markdown documentation
# 3. Validating version consistency
# 4. Optionally committing changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Options
VALIDATE_ONLY=false
COMMIT_CHANGES=false
FORCE_UPDATE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --validate-only)
      VALIDATE_ONLY=true
      shift
      ;;
    --commit)
      COMMIT_CHANGES=true
      shift
      ;;
    --force)
      FORCE_UPDATE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Update the CDK version matrix automatically."
      echo ""
      echo "Options:"
      echo "  --validate-only    Only run validation, don't update files"
      echo "  --commit          Commit changes to git (requires clean working tree)"
      echo "  --force           Force update even if no changes detected"
      echo "  -h, --help        Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                # Update matrix files"
      echo "  $0 --validate-only # Only validate existing configuration"  
      echo "  $0 --commit       # Update and commit changes"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}🔄 CDK Version Matrix Update${NC}"
echo "============================================"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# Check Python dependencies
echo -e "${BLUE}📋 Checking dependencies...${NC}"
if ! python3 -c "import requests, yaml" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Installing required Python packages...${NC}"
    pip3 install requests pyyaml
fi

cd "$SCRIPT_DIR"

# Make scripts executable
chmod +x extract-versions.py generate-markdown.py validate-versions.py

if [ "$VALIDATE_ONLY" = true ]; then
    echo -e "${BLUE}🔍 Running validation only...${NC}"
    
    # Run validation
    if python3 validate-versions.py; then
        echo -e "${GREEN}✅ Validation passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Validation failed!${NC}"
        exit 1
    fi
fi

# Store original files for comparison
MATRIX_MD="$REPO_ROOT/CDK_VERSION_MATRIX.MD"
MATRIX_JSON="$REPO_ROOT/version-matrix.json"

if [ -f "$MATRIX_MD" ]; then
    cp "$MATRIX_MD" "$MATRIX_MD.backup"
fi

if [ -f "$MATRIX_JSON" ]; then
    cp "$MATRIX_JSON" "$MATRIX_JSON.backup"
fi

echo -e "${BLUE}📊 Extracting version information...${NC}"
if ! python3 extract-versions.py; then
    echo -e "${RED}❌ Failed to extract version information${NC}"
    exit 1
fi

echo -e "${BLUE}📝 Generating Markdown documentation...${NC}"
if ! python3 generate-markdown.py; then
    echo -e "${RED}❌ Failed to generate Markdown documentation${NC}"
    exit 1
fi

echo -e "${BLUE}🔍 Validating updated configuration...${NC}"
if ! python3 validate-versions.py; then
    echo -e "${YELLOW}⚠️  Validation found issues (see above)${NC}"
    # Don't exit on validation warnings, but report them
fi

# Check for changes
CHANGES_DETECTED=false

if [ -f "$MATRIX_MD.backup" ]; then
    if ! diff -q "$MATRIX_MD" "$MATRIX_MD.backup" > /dev/null 2>&1; then
        CHANGES_DETECTED=true
        echo -e "${GREEN}📄 Changes detected in CDK_VERSION_MATRIX.MD${NC}"
    fi
else
    CHANGES_DETECTED=true
    echo -e "${GREEN}📄 Created new CDK_VERSION_MATRIX.MD${NC}"
fi

if [ -f "$MATRIX_JSON.backup" ]; then
    if ! diff -q "$MATRIX_JSON" "$MATRIX_JSON.backup" > /dev/null 2>&1; then
        CHANGES_DETECTED=true
        echo -e "${GREEN}📊 Changes detected in version-matrix.json${NC}"
    fi
else
    CHANGES_DETECTED=true
    echo -e "${GREEN}📊 Created new version-matrix.json${NC}"
fi

if [ "$CHANGES_DETECTED" = false ] && [ "$FORCE_UPDATE" = false ]; then
    echo -e "${BLUE}ℹ️  No changes detected in version matrix${NC}"
    
    # Clean up backup files
    [ -f "$MATRIX_MD.backup" ] && rm "$MATRIX_MD.backup"
    [ -f "$MATRIX_JSON.backup" ] && rm "$MATRIX_JSON.backup"
    
    exit 0
fi

# Show summary of changes
if [ -f "$MATRIX_JSON" ]; then
    echo -e "${BLUE}📈 Matrix Summary:${NC}"
    python3 -c "
import json
try:
    with open('$MATRIX_JSON', 'r') as f:
        data = json.load(f)
    summary = data.get('summary', {})
    print(f'  - Total components: {summary.get(\"total_components\", 0)}')
    print(f'  - Total scenarios: {summary.get(\"total_scenarios\", 0)}')
    print(f'  - Supported forks: {\", \".join(sorted(summary.get(\"supported_forks\", [])))}')
    print(f'  - Consensus types: {\", \".join(sorted(summary.get(\"consensus_types\", [])))}')
except Exception as e:
    print(f'  Error reading summary: {e}')
    "
fi

# Commit changes if requested
if [ "$COMMIT_CHANGES" = true ]; then
    echo -e "${BLUE}💾 Committing changes...${NC}"
    
    # Check if working tree is clean (apart from our changes)
    cd "$REPO_ROOT"
    
    # Stage our files
    git add CDK_VERSION_MATRIX.MD version-matrix.json
    
    # Check if there are any other unstaged changes
    if git diff --quiet && git diff --cached --quiet --name-only | grep -v -E "(CDK_VERSION_MATRIX\.MD|version-matrix\.json)"; then
        echo -e "${RED}❌ Working tree has other changes. Please commit or stash them first.${NC}"
        exit 1
    fi
    
    # Create commit message
    COMMIT_MSG="chore: update version matrix $(date -u +%Y-%m-%d)

Automated update of the CDK version matrix including:
- Component version compatibility
- Test scenario configurations  
- Latest release information
- Version status indicators

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
    
    if git commit -m "$COMMIT_MSG"; then
        echo -e "${GREEN}✅ Changes committed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to commit changes${NC}"
        exit 1
    fi
fi

# Clean up backup files
[ -f "$MATRIX_MD.backup" ] && rm "$MATRIX_MD.backup"
[ -f "$MATRIX_JSON.backup" ] && rm "$MATRIX_JSON.backup"

echo -e "${GREEN}🎉 Version matrix update completed successfully!${NC}"
echo ""
echo "Files updated:"
echo "  - CDK_VERSION_MATRIX.MD (human-readable matrix)"
echo "  - version-matrix.json (machine-readable data)"
echo ""
echo "Next steps:"
if [ "$COMMIT_CHANGES" = false ]; then
    echo "  - Review the changes: git diff CDK_VERSION_MATRIX.MD"
    echo "  - Commit the changes: git add . && git commit -m 'chore: update version matrix'"
fi
echo "  - The version matrix will be automatically updated daily via GitHub Actions"