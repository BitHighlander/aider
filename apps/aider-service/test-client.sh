#!/bin/bash
# Test Client for Aider Service
# This script demonstrates how to interact with the Aider service running in Docker

set -e # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_URL="http://localhost:9876/api"
TEST_REPO="https://github.com/coinmaster-gm-scribe/js-typo-test.git"
TEST_DIR="/tmp/js-typo-test-client-$(date +%s)"
THREAD_ID="client-test-$(date +%s)"

# Banner
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}        MAGA Protocol: Aider Service Test Client         ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo

# Function to check if the Aider service is running
check_service() {
  echo -e "${YELLOW}Checking if Aider service is running...${NC}"
  
  HEALTH_RESPONSE=$(curl -s "${API_URL}/health")
  
  if [[ "$HEALTH_RESPONSE" == *"UP"* ]]; then
    echo -e "${GREEN}✓ Aider service is running${NC}"
  else
    echo -e "${RED}✗ Aider service is not running${NC}"
    echo "Response: $HEALTH_RESPONSE"
    exit 1
  fi
}

# Function to clone the test repository
clone_repository() {
  echo -e "\n${YELLOW}Cloning test repository...${NC}"
  
  mkdir -p $TEST_DIR
  git clone $TEST_REPO $TEST_DIR
  
  echo -e "${GREEN}✓ Repository cloned to $TEST_DIR${NC}"
}

# Function to start an Aider instance
start_aider_instance() {
  echo -e "\n${YELLOW}Starting Aider instance...${NC}"
  
  # Get OpenAI API key from environment or parent directory .env file
  if [ -z "$OPENAI_API_KEY" ]; then
    if [ -f "../.env" ]; then
      export $(grep OPENAI_API_KEY ../.env | xargs)
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
      echo -e "${RED}OPENAI_API_KEY is not set. Please set it in the environment or in ../.env${NC}"
      exit 1
    fi
  fi
  
  START_RESPONSE=$(curl -s -X POST "${API_URL}/instances" \
    -H "Content-Type: application/json" \
    -d "{
      \"threadId\": \"${THREAD_ID}\",
      \"openAIApiKey\": \"${OPENAI_API_KEY}\",
      \"projectRoot\": \"${TEST_DIR}\",
      \"autoCommit\": true,
      \"model\": \"gpt-4\"
    }")
  
  echo "Start response: $START_RESPONSE"
  
  if [[ "$START_RESPONSE" == *"RUNNING"* ]]; then
    echo -e "${GREEN}✓ Aider instance started successfully with thread ID: $THREAD_ID${NC}"
  else
    echo -e "${RED}✗ Failed to start Aider instance${NC}"
    echo "Response: $START_RESPONSE"
    exit 1
  fi
}

# Function to check the instance status
check_instance_status() {
  echo -e "\n${YELLOW}Checking instance status...${NC}"
  
  STATUS_RESPONSE=$(curl -s "${API_URL}/instances/${THREAD_ID}")
  
  echo "Status response: $STATUS_RESPONSE"
  
  if [[ "$STATUS_RESPONSE" == *"RUNNING"* ]]; then
    echo -e "${GREEN}✓ Aider instance is running${NC}"
  else
    echo -e "${RED}✗ Aider instance is not running${NC}"
    echo "Response: $STATUS_RESPONSE"
    exit 1
  fi
}

# Function to send a command to fix JavaScript typos
fix_typos() {
  echo -e "\n${YELLOW}Sending command to fix JavaScript typos...${NC}"
  
  COMMAND_RESPONSE=$(curl -s -X POST "${API_URL}/instances/${THREAD_ID}/command" \
    -H "Content-Type: application/json" \
    -d "{
      \"command\": \"Fix all JavaScript typos in this repository. Look for syntax errors, incorrect variable references, and function name typos. Make all necessary corrections to make the code run correctly.\"
    }")
  
  echo "Command response: $COMMAND_RESPONSE"
  
  if [[ "$COMMAND_RESPONSE" == *"Command sent"* ]]; then
    echo -e "${GREEN}✓ Fix command sent successfully${NC}"
  else
    echo -e "${RED}✗ Failed to send fix command${NC}"
    echo "Response: $COMMAND_RESPONSE"
    exit 1
  fi
}

# Function to wait for changes
wait_for_changes() {
  echo -e "\n${YELLOW}Waiting for Aider to process (60 seconds)...${NC}"
  
  for i in {1..60}; do
    echo -n "."
    sleep 1
  done
  echo
  
  echo -e "${GREEN}✓ Wait completed${NC}"
}

# Function to verify changes
verify_changes() {
  echo -e "\n${YELLOW}Verifying changes...${NC}"
  
  cd $TEST_DIR
  
  # Check if files were changed
  if git status --porcelain | grep -q .; then
    echo -e "${GREEN}✓ Changes detected${NC}"
    echo "Changes made by Aider:"
    git diff --color
    
    # Try to run the fixed code
    echo -e "\n${YELLOW}Running the fixed code...${NC}"
    if node app.js; then
      echo -e "${GREEN}✓ Fixed code runs successfully${NC}"
    else
      echo -e "${RED}✗ Fixed code still has errors${NC}"
    fi
  else
    echo -e "${RED}✗ No changes detected${NC}"
  fi
  
  cd - > /dev/null
}

# Function to stop the Aider instance
stop_aider_instance() {
  echo -e "\n${YELLOW}Stopping Aider instance...${NC}"
  
  STOP_RESPONSE=$(curl -s -X DELETE "${API_URL}/instances/${THREAD_ID}")
  
  echo "Stop response: $STOP_RESPONSE"
  
  if [[ "$STOP_RESPONSE" == *"HALTED"* ]]; then
    echo -e "${GREEN}✓ Aider instance stopped successfully${NC}"
  else
    echo -e "${RED}✗ Failed to stop Aider instance${NC}"
    echo "Response: $STOP_RESPONSE"
  fi
}

# Function to clean up
cleanup() {
  echo -e "\n${YELLOW}Cleaning up...${NC}"
  
  rm -rf $TEST_DIR
  
  echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Main function
main() {
  check_service
  clone_repository
  start_aider_instance
  check_instance_status
  fix_typos
  wait_for_changes
  verify_changes
  stop_aider_instance
  cleanup
  
  echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}   MAGA Protocol: Test Client Completed Successfully    ${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

# Run the main function
main 