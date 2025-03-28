#!/bin/bash
# MAGA Protocol: End-to-End Test for Aider Service
# This script creates an Aider instance, sends a command to fix typos,
# and verifies the changes

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_URL="http://localhost:3100/api"
TEST_PROJECT="/tmp/aider-test-project"
THREAD_ID="test-$(date +%s)"

# Make sure we have an OpenAI API key
if [[ -z "${OPENAI_API_KEY}" ]]; then
  # Try to extract from the project's .env file
  if [[ -f "/Users/highlander/WebstormProjects/pioneer-desktop-v11/.env" ]]; then
    export OPENAI_API_KEY=$(grep OPENAI_API_KEY /Users/highlander/WebstormProjects/pioneer-desktop-v11/.env | cut -d '=' -f2)
  fi
  
  if [[ -z "${OPENAI_API_KEY}" ]]; then
    echo -e "${RED}Error: OPENAI_API_KEY is not set${NC}"
    echo "Please set the OPENAI_API_KEY environment variable or add it to your .env file"
    exit 1
  fi
fi

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MAGA Protocol: Aider Service End-to-End Test${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo

# Step 1: Check health status
echo -e "${YELLOW}Step 1: Checking service health...${NC}"
health_response=$(curl -s "${API_URL}/health")
# Extract just the top-level status field
status=$(echo $health_response | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ "$status" != "UP" ]]; then
  echo -e "${RED}Service health check failed. Status: $status${NC}"
  echo "Health response: $health_response"
  exit 1
fi
echo -e "${GREEN}✓ Service health check passed. Status: $status${NC}"
echo

# Step 2: Start an Aider instance for our test project
echo -e "${YELLOW}Step 2: Starting Aider instance for test project...${NC}"
start_response=$(curl -s -X POST "${API_URL}/instances" \
  -H "Content-Type: application/json" \
  -d "{
    \"threadId\": \"${THREAD_ID}\",
    \"openAIApiKey\": \"${OPENAI_API_KEY}\",
    \"projectRoot\": \"${TEST_PROJECT}\"
  }")

echo "Aider instance response: $start_response"
instance_id=$(echo $start_response | grep -o '"threadId":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$instance_id" ]]; then
  echo -e "${RED}Failed to start Aider instance${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Started Aider instance with ID: $instance_id${NC}"
echo

# Step 3: Wait a moment for Aider to initialize and verify its status
echo -e "${YELLOW}Step 3: Waiting for Aider to initialize...${NC}"
echo "Waiting 10 seconds for initialization..."
sleep 10

# Check instance status
echo "Checking instance status..."
status_response=$(curl -s "${API_URL}/instances/${THREAD_ID}")
echo "Instance status: $status_response"

# Verify instance is running
instance_state=$(echo $status_response | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ "$instance_state" != "RUNNING" ]]; then
  echo -e "${RED}Aider instance is not in RUNNING state. Current state: $instance_state${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Aider instance is in RUNNING state${NC}"
echo

# Step 4: Send a simple test command first
echo -e "${YELLOW}Step 4: Sending test command...${NC}"
test_cmd_response=$(curl -s -X POST "${API_URL}/instances/${THREAD_ID}/command" \
  -H "Content-Type: application/json" \
  -d "{
    \"command\": \"hello\"
  }")

echo "Test command response: $test_cmd_response"
test_cmd_status=$(echo $test_cmd_response | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "failed")

if [[ "$test_cmd_status" != "Command sent" ]]; then
  echo -e "${RED}Failed to send test command to Aider${NC}"
  echo -e "${YELLOW}Checking process status for debugging...${NC}"
  ps -ef | grep aider | grep -v grep
  exit 1
fi
echo -e "${GREEN}✓ Test command sent successfully${NC}"
echo

# Step 5: Send command to fix typos
echo -e "${YELLOW}Step 5: Sending command to fix typos...${NC}"
command_response=$(curl -s -X POST "${API_URL}/instances/${THREAD_ID}/command" \
  -H "Content-Type: application/json" \
  -d "{
    \"command\": \"Fix all typos and errors in hello.js\"
  }")

echo "Command response: $command_response"
command_status=$(echo $command_response | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "failed")

if [[ "$command_status" != "Command sent" ]]; then
  echo -e "${RED}Failed to send command to Aider${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Command sent successfully${NC}"
echo

# Step 6: Wait for Aider to process the command
echo -e "${YELLOW}Step 6: Waiting for Aider to process command (60 seconds)...${NC}"
for i in {1..60}; do
  echo -n "."
  sleep 1
done
echo
echo -e "${GREEN}✓ Waited for processing${NC}"
echo

# Step 7: Check the content of the file to see if typos were fixed
echo -e "${YELLOW}Step 7: Checking if typos were fixed...${NC}"
cat ${TEST_PROJECT}/hello.js
echo

# Step 8: Show git diff to see what changed
echo -e "${YELLOW}Step 8: Showing Git diff to see changes...${NC}"
(cd ${TEST_PROJECT} && git diff)
echo

# Step 9: Stop the Aider instance
echo -e "${YELLOW}Step 9: Stopping Aider instance...${NC}"
stop_response=$(curl -s -X DELETE "${API_URL}/instances/${THREAD_ID}")
echo "Stop response: $stop_response"
stop_status=$(echo $stop_response | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "failed")

if [[ "$stop_status" != "HALTED" ]]; then
  echo -e "${RED}Failed to stop Aider instance${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Stopped Aider instance${NC}"
echo

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}End-to-End Test Completed${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo

echo "You can check the Git diff to see what changes Aider made:"
echo "cd ${TEST_PROJECT} && git diff"
