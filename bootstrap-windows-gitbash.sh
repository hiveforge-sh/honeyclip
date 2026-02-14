#!/usr/bin/env bash
#
# Git Bash wrapper for Windows bootstrap
# This script launches the PowerShell bootstrap script from Git Bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}=========================================="
echo "  honeyclip bootstrap (Windows)"
echo -e "==========================================${NC}"
echo ""
echo -e "${YELLOW}Launching PowerShell bootstrap script...${NC}"
echo ""
echo "This will run bootstrap.ps1 in PowerShell."
echo ""
read -p "Run as administrator? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Starting PowerShell as administrator...${NC}"
    # Convert Unix path to Windows path
    script_dir=$(pwd -W)
    powershell.exe -Command "Start-Process powershell -Verb RunAs -ArgumentList \"-ExecutionPolicy Bypass -File '$script_dir\\bootstrap.ps1'\""
    echo ""
    echo -e "${GREEN}PowerShell window opened. Check that window for progress.${NC}"
else
    echo -e "${GREEN}Starting PowerShell (non-admin)...${NC}"
    powershell.exe -ExecutionPolicy Bypass -File ./bootstrap.ps1
fi

echo ""
echo -e "${GREEN}Done!${NC}"
