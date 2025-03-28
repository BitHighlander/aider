#!/bin/bash
# MAGA Workflow Validation Script for Aider Service
# Implements Guild Protocol MAGA-DEPLOY-001
# Validates that all services are ready for deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BRANCH="develop"
ENVIRONMENTS=("development" "staging" "production")
SERVICES=("aider-service")
VERBOSE=false
TEST_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -b|--branch)
      BRANCH="$2"
      shift 2
      ;;
    -e|--environments)
      IFS=',' read -ra ENVIRONMENTS <<< "$2"
      shift 2
      ;;
    -s|--services)
      IFS=',' read -ra SERVICES <<< "$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -t|--test)
      TEST_MODE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo
      echo "Options:"
      echo "  -b, --branch BRANCH     Git branch to validate (default: develop)"
      echo "  -e, --environments ENV   Comma-separated environments to check"
      echo "                          (default: development,staging,production)"
      echo "  -s, --services SERVICES  Comma-separated services to check"
      echo "                          (default: aider-service)"
      echo "  -v, --verbose            Enable verbose output"
      echo "  -t, --test               Test mode (skips actual deployment checks)"
      echo "  -h, --help               Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate branch
if [[ ! "$BRANCH" =~ ^(develop|master|feature/.+)$ ]]; then
  echo -e "${RED}Invalid branch format: $BRANCH${NC}"
  echo "Branch should be 'develop', 'master', or 'feature/*'"
  exit 1
fi

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}🔍 MAGA Workflow Validation - Aider Service${NC}"
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}Branch: $BRANCH${NC}"
echo -e "${BLUE}Environments: ${ENVIRONMENTS[*]}${NC}"
echo -e "${BLUE}Services: ${SERVICES[*]}${NC}"
echo

# Function to check if tests pass
validate_tests() {
  echo -e "${YELLOW}Running test suite...${NC}"
  
  if [[ $TEST_MODE == true ]]; then
    echo -e "${YELLOW}Test mode enabled, skipping actual test execution${NC}"
    echo -e "${GREEN}✓ Tests passed (simulated)${NC}"
    return 0
  fi
  
  # Run tests using npm
  if npm test --prefix /Users/highlander/WebstormProjects/pioneer-desktop-v11/apps/aider-service; then
    echo -e "${GREEN}✓ All tests passed${NC}"
    return 0
  else
    echo -e "${RED}✗ Tests failed${NC}"
    return 1
  fi
}

# Function to check build
validate_build() {
  echo -e "${YELLOW}Building the application...${NC}"
  
  if [[ $TEST_MODE == true ]]; then
    echo -e "${YELLOW}Test mode enabled, skipping actual build${NC}"
    echo -e "${GREEN}✓ Build succeeded (simulated)${NC}"
    return 0
  fi
  
  # Run build using npm
  if npm run build --prefix /Users/highlander/WebstormProjects/pioneer-desktop-v11/apps/aider-service; then
    echo -e "${GREEN}✓ Build succeeded${NC}"
    return 0
  else
    echo -e "${RED}✗ Build failed${NC}"
    return 1
  fi
}

# Function to check linting
validate_linting() {
  echo -e "${YELLOW}Running linters...${NC}"
  
  if [[ $TEST_MODE == true ]]; then
    echo -e "${YELLOW}Test mode enabled, skipping actual linting${NC}"
    echo -e "${GREEN}✓ Linting passed (simulated)${NC}"
    return 0
  fi
  
  # Run lint using npm
  if npm run lint --prefix /Users/highlander/WebstormProjects/pioneer-desktop-v11/apps/aider-service; then
    echo -e "${GREEN}✓ Linting passed${NC}"
    return 0
  else
    echo -e "${RED}✗ Linting failed${NC}"
    return 1
  fi
}

# Function to check deployment health
validate_deployment_health() {
  local service=$1
  local environment=$2
  local script="/Users/highlander/WebstormProjects/pioneer-desktop-v11/apps/aider-service/scripts/verify-deployment-health.sh"
  
  echo -e "${YELLOW}Checking $service deployment in $environment environment...${NC}"
  
  if [[ $TEST_MODE == true ]]; then
    echo -e "${YELLOW}Test mode enabled, skipping actual deployment check${NC}"
    echo -e "${GREEN}✓ Deployment health check passed (simulated)${NC}"
    return 0
  fi
  
  # Make sure script exists and is executable
  if [[ ! -x "$script" ]]; then
    echo -e "${RED}Deployment health check script not found or not executable: $script${NC}"
    return 1
  fi
  
  # Run deployment health check
  if $script -s "$service" -e "$environment" ${VERBOSE:+-v}; then
    echo -e "${GREEN}✓ Deployment health check passed for $service in $environment${NC}"
    return 0
  else
    result=$?
    if [[ $result -eq 2 ]]; then
      echo -e "${YELLOW}⚠ Deployment health check reports degraded state for $service in $environment${NC}"
      return 2
    else
      echo -e "${RED}✗ Deployment health check failed for $service in $environment${NC}"
      return 1
    fi
  fi
}

# Function to generate MAGA status report
generate_maga_report() {
  local report_file="/Users/highlander/WebstormProjects/pioneer-desktop-v11/apps/aider-service/maga-status-report.md"
  local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  echo -e "${YELLOW}Generating MAGA status report...${NC}"
  
  # Create header
  cat > "$report_file" << EOL
# MAGA Status Report - Aider Service

**Generated:** $timestamp  
**Branch:** $BRANCH  
**MAGA Protocol:** MAGA-DEPLOY-001

## Validation Results

| Check | Status | Details |
|-------|--------|---------|
EOL

  # Add test results
  for check in "${!check_results[@]}"; do
    status="${check_statuses[$check]}"
    result="${check_results[$check]}"
    
    echo "| $check | $status | $result |" >> "$report_file"
  done
  
  # Add environment status
  echo -e "\n## Environment Status\n" >> "$report_file"
  
  for environment in "${ENVIRONMENTS[@]}"; do
    echo -e "### $environment Environment\n" >> "$report_file"
    echo "| Service | Status | Details |" >> "$report_file"
    echo "|---------|--------|---------|" >> "$report_file"
    
    for service in "${SERVICES[@]}"; do
      key="${service}_${environment}"
      status="${env_statuses[$key]}"
      result="${env_results[$key]}"
      
      echo "| $service | $status | $result |" >> "$report_file"
    done
    
    echo -e "\n" >> "$report_file"
  done
  
  # Add overall status
  echo -e "## Overall MAGA Status\n" >> "$report_file"
  echo -e "**Status:** $overall_status\n" >> "$report_file"
  echo -e "**Recommendation:** $recommendation\n" >> "$report_file"
  
  echo -e "${GREEN}MAGA status report generated: $report_file${NC}"
}

# Initialize result tracking
declare -A check_results
declare -A check_statuses
declare -A env_results
declare -A env_statuses

overall_status="GREEN"
recommendation="Proceed with deployment"

# Run code quality checks
echo -e "${BLUE}▶ Running Code Quality Checks${NC}"
echo "========================================="

# Linting check
if validate_linting; then
  check_results["Linting"]="All linting rules passed"
  check_statuses["Linting"]="✅"
else
  check_results["Linting"]="Linting errors detected"
  check_statuses["Linting"]="❌"
  overall_status="RED"
  recommendation="Fix linting errors before proceeding"
fi

# Test suite check
if validate_tests; then
  check_results["Tests"]="All tests passed"
  check_statuses["Tests"]="✅"
else
  check_results["Tests"]="Test failures detected"
  check_statuses["Tests"]="❌"
  overall_status="RED"
  recommendation="Fix failing tests before proceeding"
fi

# Build check
if validate_build; then
  check_results["Build"]="Build succeeded"
  check_statuses["Build"]="✅"
else
  check_results["Build"]="Build failed"
  check_statuses["Build"]="❌"
  overall_status="RED"
  recommendation="Fix build errors before proceeding"
fi

echo

# Check deployment health for each service and environment
echo -e "${BLUE}▶ Running Deployment Health Checks${NC}"
echo "========================================="

for environment in "${ENVIRONMENTS[@]}"; do
  for service in "${SERVICES[@]}"; do
    result=$(validate_deployment_health "$service" "$environment")
    status=$?
    
    key="${service}_${environment}"
    
    if [[ $status -eq 0 ]]; then
      env_results[$key]="Healthy"
      env_statuses[$key]="✅"
    elif [[ $status -eq 2 ]]; then
      env_results[$key]="Degraded"
      env_statuses[$key]="⚠️"
      
      if [[ $overall_status == "GREEN" ]]; then
        overall_status="YELLOW"
        recommendation="Service is degraded, review issues before proceeding"
      fi
    else
      env_results[$key]="Unhealthy"
      env_statuses[$key]="❌"
      overall_status="RED"
      recommendation="Fix deployment issues before proceeding"
    fi
  done
done

echo

# Generate MAGA status report
generate_maga_report

# Display MAGA status
echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}🚦 MAGA Status: $overall_status${NC}"
echo -e "${BLUE}===============================================${NC}"

case $overall_status in
  "GREEN")
    echo -e "${GREEN}✅ All checks passed. Ready for deployment!${NC}"
    ;;
  "YELLOW")
    echo -e "${YELLOW}⚠️ Minor issues detected. Review before proceeding.${NC}"
    ;;
  "RED")
    echo -e "${RED}❌ Validation failed. Deployment is blocked.${NC}"
    ;;
esac

echo -e "${BLUE}Recommendation: $recommendation${NC}"
echo -e "${BLUE}See full report for details: maga-status-report.md${NC}"

# Exit with appropriate status code
case $overall_status in
  "GREEN")
    exit 0
    ;;
  "YELLOW")
    exit 2
    ;;
  "RED")
    exit 1
    ;;
esac
