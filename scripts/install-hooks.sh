#!/bin/bash
#
# Install Git hooks for honeyclip development
#
# Usage:
#   ./scripts/install-hooks.sh

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Installing Git hooks...${NC}\n"

# Get the git directory
GIT_DIR=$(git rev-parse --git-dir)

# Create hooks directory if it doesn't exist
mkdir -p "$GIT_DIR/hooks"

# Install pre-commit hook
if [ -f "$GIT_DIR/hooks/pre-commit" ]; then
  echo "⚠  Pre-commit hook already exists, backing up to pre-commit.old"
  mv "$GIT_DIR/hooks/pre-commit" "$GIT_DIR/hooks/pre-commit.old"
fi

cp scripts/git-hooks/pre-commit "$GIT_DIR/hooks/pre-commit"
chmod +x "$GIT_DIR/hooks/pre-commit"

echo -e "${GREEN}✓${NC} Pre-commit hook installed"

# Optional: Install other hooks here (prepare-commit-msg, commit-msg, etc.)

echo -e "\n${GREEN}✓ Git hooks installed successfully!${NC}"
echo ""
echo "Configuration options (add to ~/.bashrc or ~/.zshrc):"
echo "  export PRECOMMIT_CHECK_WINDOWS=1  # Enable Windows cross-compile check (slow)"
echo ""
echo "Skip hook when needed:"
echo "  git commit --no-verify"
echo ""
echo "Uninstall:"
echo "  rm $GIT_DIR/hooks/pre-commit"
