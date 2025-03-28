#!/bin/bash
# MAGA-compliant Deployment Health Verification Script for Aider Service
# Follows Guild Protocol MAGA-DEPLOY-001

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SERVICE="aider-service"
ENVIRONMENT="development"
TIMEOUT=5
VERBOSE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -s|--service)
      SERVICE="$2"
      shift 2
      ;;
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo
      echo "Options:"
      echo "  -s, --service SERVICE    Service name (default: aider-service)"
      echo "  -e, --environment ENV    Environment (development, staging, production)"
      echo "  -t, --timeout SECONDS    Timeout in seconds for health checks (default: 5)"
      echo "  -v, --verbose            Enable verbose output"
      echo "  -h, --help               Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Determine service URL based on environment
case $ENVIRONMENT in
  development)
    BASE_URL="http://localhost:3100"
    ;;
  staging)
    BASE_URL="https://staging.aider-service.pioneerdesktop.com"
    ;;
  production)
    BASE_URL="https://aider-service.pioneerdesktop.com"
    ;;
  *)
    echo -e "${RED}Invalid environment: $ENVIRONMENT${NC}"
    exit 1
    ;;
esac

echo -e "${BLUE}MAGA Verification: $SERVICE in $ENVIRONMENT environment${NC}"
echo -e "${BLUE}Base URL: $BASE_URL${NC}"
echo

# Function to check HTTP endpoint
check_endpoint() {
  local endpoint=$1
  local expected_status=${2:-200}
  local url="${BASE_URL}${endpoint}"
  
  echo -e "${YELLOW}Checking endpoint: $url${NC}"
  
  # Use curl to check endpoint
  if [[ $VERBOSE == true ]]; then
    response=$(curl -s -w "\n%{http_code}" "$url" -m "$TIMEOUT")
  else
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" -m "$TIMEOUT")
  fi
  
  status_code=$(echo "$response" | tail -n1)
  
  if [[ $status_code -eq $expected_status ]]; then
    echo -e "${GREEN}✓ Endpoint $endpoint returned $status_code (expected: $expected_status)${NC}"
    return 0
  else
    echo -e "${RED}✗ Endpoint $endpoint returned $status_code (expected: $expected_status)${NC}"
    return 1
  fi
}

# Check API health endpoint
check_health() {
  local endpoint="/api/health"
  local url="${BASE_URL}${endpoint}"
  
  echo -e "${YELLOW}Checking health endpoint: $url${NC}"
  
  # Get health check response
  response=$(curl -s "$url" -m "$TIMEOUT")
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}✗ Failed to connect to health endpoint${NC}"
    return 1
  fi
  
  # Parse status field
  status=$(echo "$response" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  
  if [[ "$status" == "UP" ]]; then
    echo -e "${GREEN}✓ Service status is UP${NC}"
    
    if [[ $VERBOSE == true ]]; then
      echo -e "${BLUE}Health response:${NC}"
      echo "$response" | jq . 2>/dev/null || echo "$response"
    fi
    
    return 0
  elif [[ "$status" == "DEGRADED" ]]; then
    echo -e "${YELLOW}⚠ Service status is DEGRADED${NC}"
    echo -e "${BLUE}Health response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    return 2
  else
    echo -e "${RED}✗ Service status is DOWN or unknown: $status${NC}"
    echo -e "${BLUE}Health response:${NC}"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    return 1
  fi
}

# Verify API documentation
check_docs() {
  local endpoint="/docs"
  local url="${BASE_URL}${endpoint}"
  
  echo -e "${YELLOW}Checking API documentation: $url${NC}"
  
  # Check docs endpoint
  curl -s -o /dev/null -w "%{http_code}" "$url" -m "$TIMEOUT" | grep -q 200
  
  if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✓ API documentation is available${NC}"
    return 0
  else
    echo -e "${RED}✗ API documentation is not available${NC}"
    return 1
  fi
}

# Check OpenAPI definition
check_openapi() {
  local endpoint="/openapi.json"
  local url="${BASE_URL}${endpoint}"
  
  echo -e "${YELLOW}Checking OpenAPI definition: $url${NC}"
  
  # Get OpenAPI definition
  response=$(curl -s "$url" -m "$TIMEOUT")
  
  if [[ $? -ne 0 ]]; then
    echo -e "${RED}✗ Failed to retrieve OpenAPI definition${NC}"
    return 1
  fi
  
  # Check if it's valid JSON and has openapi field
  echo "$response" | jq -e '.openapi' >/dev/null 2>&1
  
  if [[ $? -eq 0 ]]; then
    openapi_version=$(echo "$response" | jq -r '.openapi')
    echo -e "${GREEN}✓ Valid OpenAPI definition (version $openapi_version)${NC}"
    return 0
  else
    echo -e "${RED}✗ Invalid OpenAPI definition${NC}"
    return 1
  fi
}

echo "🔍 Running MAGA health verification checks..."
echo

# Run all checks
results=()
descriptions=()

# Basic endpoint check
check_endpoint "/"
results+=($?)
descriptions+=("Base endpoint")

# Health check
check_health
results+=($?)
descriptions+=("Health endpoint")

# Documentation check
check_docs
results+=($?)
descriptions+=("API documentation")

# OpenAPI definition check
check_openapi
results+=($?)
descriptions+=("OpenAPI definition")

echo
echo "📊 MAGA Verification Results:"
echo "================================="

# Calculate success rate
success=0
degraded=0
failed=0

for i in "${!results[@]}"; do
  if [[ ${results[$i]} -eq 0 ]]; then
    success=$((success + 1))
    echo -e "${GREEN}✓ ${descriptions[$i]}${NC}"
  elif [[ ${results[$i]} -eq 2 ]]; then
    degraded=$((degraded + 1))
    echo -e "${YELLOW}⚠ ${descriptions[$i]} (degraded)${NC}"
  else
    failed=$((failed + 1))
    echo -e "${RED}✗ ${descriptions[$i]}${NC}"
  fi
done

total=${#results[@]}
success_rate=$((success * 100 / total))

echo
echo "================================="
echo -e "Checks passed: ${GREEN}$success${NC}/$total ($success_rate%)"

if [[ $degraded -gt 0 ]]; then
  echo -e "Degraded components: ${YELLOW}$degraded${NC}"
fi

if [[ $failed -gt 0 ]]; then
  echo -e "Failed checks: ${RED}$failed${NC}"
fi

# MAGA status determination
if [[ $failed -gt 0 ]]; then
  echo
  echo -e "${RED}❌ MAGA STATUS: RED${NC}"
  echo -e "${RED}Service verification failed. Master branch deployment is blocked.${NC}"
  exit 1
elif [[ $degraded -gt 0 ]]; then
  echo
  echo -e "${YELLOW}⚠ MAGA STATUS: YELLOW${NC}"
  echo -e "${YELLOW}Service is degraded. Review issues before proceeding with deployment.${NC}"
  exit 2
else
  echo
  echo -e "${GREEN}✅ MAGA STATUS: GREEN${NC}"
  echo -e "${GREEN}All health checks passed. Service is ready for deployment.${NC}"
  exit 0
fi
