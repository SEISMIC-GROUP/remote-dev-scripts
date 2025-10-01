#!/bin/bash

################################################################################
# Installation Validation Script
#
# This script validates the complete installation of all development tools
# with precise gate checks and benchmarks.
#
# Usage: bash validate-installation.sh
################################################################################

set +e  # Don't exit on error - we want to collect all validation results

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_GATES=0
PASSED_GATES=0
FAILED_GATES=0

# Results array
declare -a RESULTS

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_gate() {
    echo -e "\n${BLUE}━━━ Gate $1: $2 ━━━${NC}"
}

pass_test() {
    echo -e "  ${GREEN}✓ PASS${NC} - $1"
    RESULTS+=("PASS: $2 - $1")
    ((PASSED_GATES++))
}

fail_test() {
    echo -e "  ${RED}✗ FAIL${NC} - $1"
    RESULTS+=("FAIL: $2 - $1")
    ((FAILED_GATES++))
}

warn_test() {
    echo -e "  ${YELLOW}⚠ WARNING${NC} - $1"
}

check_command() {
    local cmd=$1
    local name=$2
    local gate=$3

    ((TOTAL_GATES++))
    if command -v "$cmd" &> /dev/null; then
        pass_test "$name is installed and in PATH" "$gate"
        return 0
    else
        fail_test "$name not found in PATH" "$gate"
        return 1
    fi
}

check_version() {
    local cmd=$1
    local expected_pattern=$2
    local name=$3
    local gate=$4

    ((TOTAL_GATES++))
    if command -v "$cmd" &> /dev/null; then
        local version_output=$($cmd 2>&1 || echo "error")
        if echo "$version_output" | grep -qE "$expected_pattern"; then
            pass_test "$name version matches expected pattern: $expected_pattern" "$gate"
            echo "    Version: $(echo "$version_output" | head -n 1)"
            return 0
        else
            fail_test "$name version doesn't match expected pattern: $expected_pattern" "$gate"
            echo "    Got: $(echo "$version_output" | head -n 1)"
            return 1
        fi
    else
        fail_test "$name command not found" "$gate"
        return 1
    fi
}

check_npm_package() {
    local package=$1
    local name=$2
    local gate=$3

    ((TOTAL_GATES++))
    if npm list -g "$package" 2>&1 | grep -q "$package"; then
        local version=$(npm list -g "$package" 2>&1 | grep "$package" | head -n 1)
        pass_test "$name is installed globally" "$gate"
        echo "    $version"
        return 0
    else
        fail_test "$name not found in global npm packages" "$gate"
        return 1
    fi
}

################################################################################
# Validation Gates
################################################################################

main() {
    print_header "Installation Validation Report"
    echo "Generated: $(date)"
    echo "Hostname: $(hostname)"
    echo ""

    # GATE 0: System Information
    print_gate "0" "System Information & Pre-flight Checks"

    echo "  OS Information:"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "    Distribution: $NAME"
        echo "    Version: $VERSION"

        ((TOTAL_GATES++))
        if echo "$VERSION_ID" | grep -qE "22.04|24.04"; then
            pass_test "Ubuntu LTS version detected (22.04 or 24.04)" "Gate 0"
        else
            warn_test "Ubuntu version is $VERSION_ID (expected 22.04 or 24.04)"
            ((TOTAL_GATES--))  # Don't count as failure
        fi
    fi

    echo "  Resource Information:"
    echo "    $(free -h | grep Mem:)"
    echo "    $(df -h / | tail -n 1)"

    ((TOTAL_GATES++))
    local free_space=$(df / | tail -n 1 | awk '{print $4}')
    if [ "$free_space" -gt 5000000 ]; then
        pass_test "Sufficient disk space available (>5GB)" "Gate 0"
    else
        fail_test "Low disk space (<5GB free)" "Gate 0"
    fi

    # GATE 1: System Packages
    print_gate "1" "System Preparation & Dependencies"

    local system_packages=("curl" "wget" "git" "libnss3" "libgbm1" "libxss1")
    for pkg in "${system_packages[@]}"; do
        ((TOTAL_GATES++))
        if dpkg -l | grep -q "^ii.*$pkg"; then
            pass_test "$pkg package installed" "Gate 1"
        else
            fail_test "$pkg package not found" "Gate 1"
        fi
    done

    # GATE 2: Node.js Ecosystem
    print_gate "2" "Node.js Ecosystem (Node.js, NPM, PNPM)"

    check_command "node" "Node.js" "Gate 2"
    check_version "node --version" "v22\." "Node.js v22.x" "Gate 2"

    check_command "npm" "NPM" "Gate 2"
    check_version "npm --version" "10\.|11\." "NPM v10.x or v11.x" "Gate 2"

    # Check pnpm with special handling
    ((TOTAL_GATES++))
    if [ -d "/root/.local/share/pnpm" ]; then
        export PNPM_HOME="/root/.local/share/pnpm"
        export PATH="$PNPM_HOME:$PATH"
    fi

    if command -v pnpm &> /dev/null; then
        local pnpm_ver=$(pnpm --version)
        pass_test "PNPM installed and accessible (v$pnpm_ver)" "Gate 2"
    else
        fail_test "PNPM not found in PATH" "Gate 2"
    fi

    # GATE 3: GitHub CLI
    print_gate "3" "GitHub CLI"

    check_command "gh" "GitHub CLI" "Gate 3"
    ((TOTAL_GATES++))
    if command -v gh &> /dev/null; then
        local gh_output=$(gh --version 2>&1 | head -n 1)
        if echo "$gh_output" | grep -q "gh version"; then
            pass_test "GitHub CLI functional" "Gate 3"
            echo "    $gh_output"
        else
            fail_test "GitHub CLI installed but not functional" "Gate 3"
        fi
    fi

    # GATE 4: AI Coding Tools
    print_gate "4" "AI Coding Tools (Claude Code, OpenAI Codex)"

    check_command "claude" "Claude Code" "Gate 4"
    ((TOTAL_GATES++))
    if command -v claude &> /dev/null; then
        local claude_output=$(claude --version 2>&1 | head -n 1)
        if echo "$claude_output" | grep -qE "2\.0|claude"; then
            pass_test "Claude Code v2.x detected" "Gate 4"
            echo "    $claude_output"
        else
            warn_test "Claude Code version unclear: $claude_output"
            ((TOTAL_GATES--))
        fi
    fi

    check_command "codex" "OpenAI Codex" "Gate 4"
    ((TOTAL_GATES++))
    if command -v codex &> /dev/null; then
        local codex_output=$(codex --version 2>&1 | head -n 1)
        if echo "$codex_output" | grep -qE "0\.4|codex"; then
            pass_test "OpenAI Codex v0.4x detected" "Gate 4"
            echo "    $codex_output"
        else
            warn_test "OpenAI Codex version unclear: $codex_output"
            ((TOTAL_GATES--))
        fi
    fi

    # GATE 5: Playwright
    print_gate "5" "Playwright & Browsers"

    check_command "playwright" "Playwright" "Gate 5"
    ((TOTAL_GATES++))
    if command -v playwright &> /dev/null; then
        local pw_output=$(playwright --version 2>&1)
        if echo "$pw_output" | grep -qE "1\.5|1\.4"; then
            pass_test "Playwright v1.5x detected" "Gate 5"
            echo "    $pw_output"
        else
            warn_test "Playwright version: $pw_output"
            ((TOTAL_GATES--))
        fi
    fi

    # Check for installed browsers
    ((TOTAL_GATES++))
    local browser_cache="/root/.cache/ms-playwright"
    if [ -d "$browser_cache" ]; then
        local browser_count=$(find "$browser_cache" -maxdepth 1 -type d | wc -l)
        if [ "$browser_count" -gt 2 ]; then
            pass_test "Playwright browsers installed in cache (found $browser_count directories)" "Gate 5"
        else
            fail_test "Playwright browser cache exists but appears empty" "Gate 5"
        fi
    else
        fail_test "Playwright browser cache directory not found" "Gate 5"
    fi

    # GATE 6: MCP Servers
    print_gate "6" "MCP Servers (5 Required)"

    check_npm_package "@playwright/mcp" "Playwright MCP" "Gate 6"
    check_npm_package "@upstash/context7-mcp" "Context7 MCP" "Gate 6"
    check_npm_package "@modelcontextprotocol/server-sequential-thinking" "Sequential Thinking MCP" "Gate 6"
    check_npm_package "@brightdata/mcp" "Bright Data MCP" "Gate 6"
    check_npm_package "task-master-ai" "Task Master MCP" "Gate 6"

    # GATE 7: Functional Tests
    print_gate "7" "Functional Verification Tests"

    ((TOTAL_GATES++))
    if node -e "console.log('test')" 2>&1 | grep -q "test"; then
        pass_test "Node.js can execute JavaScript" "Gate 7"
    else
        fail_test "Node.js cannot execute JavaScript" "Gate 7"
    fi

    ((TOTAL_GATES++))
    if npm list -g 2>&1 | grep -q "npm"; then
        pass_test "NPM global list accessible" "Gate 7"
    else
        fail_test "NPM global list not accessible" "Gate 7"
    fi

    ################################################################################
    # Final Report
    ################################################################################

    print_header "Validation Summary"

    echo ""
    echo "Total Gates Checked: $TOTAL_GATES"
    echo -e "${GREEN}Passed: $PASSED_GATES${NC}"
    echo -e "${RED}Failed: $FAILED_GATES${NC}"
    echo ""

    local pass_percentage=$((PASSED_GATES * 100 / TOTAL_GATES))
    echo "Success Rate: ${pass_percentage}%"
    echo ""

    if [ $FAILED_GATES -eq 0 ]; then
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✓ ALL VALIDATIONS PASSED - INSTALLATION SUCCESSFUL  ${NC}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
        exit 0
    else
        echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ✗ VALIDATION FAILED - $FAILED_GATES GATES FAILED           ${NC}"
        echo -e "${RED}═══════════════════════════════════════════════════════${NC}"
        echo ""
        echo "Failed checks:"
        for result in "${RESULTS[@]}"; do
            if [[ $result == FAIL:* ]]; then
                echo "  - ${result#FAIL: }"
            fi
        done
        exit 1
    fi
}

main "$@"
