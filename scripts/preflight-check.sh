#!/bin/bash
#
# Pre-flight Check Script
# Validates prerequisites before running setup
#

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}!${NC} $1"
}

echo "=========================================="
echo "Factorio Server Automation - Pre-flight Check"
echo "=========================================="
echo ""

PASS=0
FAIL=0
WARN=0

# Check AWS CLI
echo "Checking AWS CLI..."
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    check_pass "AWS CLI installed (version $AWS_VERSION)"
    ((PASS++))
else
    check_fail "AWS CLI not installed"
    echo "  Install: https://aws.amazon.com/cli/"
    ((FAIL++))
fi

# Check AWS credentials
echo "Checking AWS credentials..."
if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    check_pass "AWS credentials configured (Account: $ACCOUNT_ID)"
    ((PASS++))
else
    check_fail "AWS credentials not configured"
    echo "  Run: aws configure"
    ((FAIL++))
fi

# Check configuration file
echo "Checking configuration..."
if [ -f "config/factorio-server.conf" ]; then
    check_pass "Configuration file exists (config/factorio-server.conf)"
    ((PASS++))
else
    check_warn "Configuration file not found"
    echo "  Run: cp config/factorio-server.conf.example config/factorio-server.conf"
    ((WARN++))
fi

# Check jq (optional)
echo "Checking optional tools..."
if command -v jq &> /dev/null; then
    check_pass "jq installed (for JSON processing)"
    ((PASS++))
else
    check_warn "jq not installed (optional but recommended)"
    echo "  Install: https://stedolan.github.io/jq/download/"
    ((WARN++))
fi

# Check Terraform
echo "Checking Terraform..."
if command -v terraform &> /dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -1 | awk '{print $2}' | sed 's/v//')
    check_pass "Terraform installed (version $TF_VERSION)"
    ((PASS++))
else
    check_fail "Terraform not installed (required for AWS setup)"
    echo "  Install: https://www.terraform.io/downloads"
    ((FAIL++))
fi

# Check SSH
echo "Checking SSH client..."
if command -v ssh &> /dev/null; then
    SSH_VERSION=$(ssh -V 2>&1 | cut -d' ' -f1)
    check_pass "SSH client available ($SSH_VERSION)"
    ((PASS++))
else
    check_fail "SSH client not found"
    ((FAIL++))
fi

# Check scripts are executable
echo "Checking script permissions..."
SCRIPTS_OK=true
for script in scripts/*.sh; do
    if [ ! -x "$script" ]; then
        SCRIPTS_OK=false
        break
    fi
done

if [ "$SCRIPTS_OK" = true ]; then
    check_pass "All scripts are executable"
    ((PASS++))
else
    check_warn "Some scripts are not executable"
    echo "  Run: chmod +x scripts/*.sh"
    ((WARN++))
fi

# Summary
echo ""
echo "=========================================="
echo "Summary:"
echo "=========================================="
echo -e "${GREEN}Passed: $PASS${NC}"
if [ $WARN -gt 0 ]; then
    echo -e "${YELLOW}Warnings: $WARN${NC}"
fi
if [ $FAIL -gt 0 ]; then
    echo -e "${RED}Failed: $FAIL${NC}"
fi
echo ""

if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! You're ready to run setup.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review config/factorio-server.conf"
    echo "  2. Run: ./scripts/setup-aws.sh"
    exit 0
elif [ $FAIL -eq 0 ]; then
    echo -e "${YELLOW}! Some optional items missing, but you can proceed.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Address warnings above (optional)"
    echo "  2. Review config/factorio-server.conf"
    echo "  3. Run: ./scripts/setup-aws.sh"
    exit 0
else
    echo -e "${RED}✗ Some required prerequisites are missing.${NC}"
    echo "Please address the failed checks above before proceeding."
    exit 1
fi
