#!/bin/bash
# End-to-End Test Script for Aider Service
# Tests the complete flow from API to code fixes

set -e # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SERVICE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$SERVICE_ROOT/../.." && pwd)"
TEST_PROJECT_DIR="/tmp/aider-e2e-test-$(date +%s)"
TEST_SERVER_PORT=3100
TIMEOUT=300 # 5 minutes timeout for entire test

# Function to load environment variables
load_env_vars() {
    echo -e "${YELLOW}Loading environment variables...${NC}"
    
    # Try loading from service .env
    if [ -f "$SERVICE_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from service .env file...${NC}"
        export $(grep -v '^#' "$SERVICE_ROOT/.env" | grep -E 'OPENAI_API_KEY|MONGO_URI|PORT' | xargs)
    fi
    
    # Try loading from project root .env if still not set
    if [ -z "$OPENAI_API_KEY" ] && [ -f "$PROJECT_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from project root .env file...${NC}"
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | grep OPENAI_API_KEY | xargs)
    fi
    
    # Set defaults if not specified
    if [ -z "$PORT" ]; then
        export PORT=$TEST_SERVER_PORT
    fi
    
    if [ -z "$MONGO_URI" ]; then
        export MONGO_URI="mongodb://localhost:27017/aider-service-test"
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to setup the test repository
setup_test_repo() {
    echo -e "\n${BLUE}Setting up test repository...${NC}"
    
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Initialize git repository
    echo -e "${YELLOW}Initializing git repository...${NC}"
    git init &> /dev/null
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"
    
    # Create package.json
    echo -e "${YELLOW}Creating package.json...${NC}"
    cat > package.json << 'EOF'
{
  "name": "aider-test-project",
  "version": "1.0.0",
  "description": "Test project for Aider E2E testing",
  "main": "index.js",
  "scripts": {
    "test": "node index.js"
  },
  "author": "Aider Test",
  "license": "MIT"
}
EOF
    
    # Create a JavaScript file with deliberate errors
    echo -e "${YELLOW}Creating JavaScript files with errors...${NC}"
    
    # Main index.js file that imports and uses utils.js
    cat > index.js << 'EOF'
const utils = require('./utils');

// Try to use the greeting function
try {
    const result = utils.greet('World');
    console.log('Greeting function result:', result);
} catch (error) {
    console.error('Error in greeting function:', error.message);
}

// Try to use the calculator functions
try {
    const sum = utils.calculateSum(5, 10);
    console.log('Sum calculation result:', sum);
} catch (error) {
    console.error('Error in sum calculation:', error.message);
}

try {
    const product = utils.calculateProduct(5, 10);
    console.log('Product calculation result:', product);
} catch (error) {
    console.error('Error in product calculation:', error.message);
}
EOF
    
    # Utils.js with deliberate bugs
    cat > utils.js << 'EOF'
// This utils file contains deliberate errors

/**
 * Greets a person by name
 * @param {string} name The name to greet
 * @returns {string} The greeting message
 */
function greet(name) {
    // BUG: Using 'nme' instead of 'name'
    console.log("Hello, " + nme + "!");
    return "Greeting completed";
}

/**
 * Calculates the sum of two numbers
 * @param {number} a First number
 * @param {number} b Second number
 * @returns {number} The sum of a and b
 */
function calculateSum(a, b) {
    // BUG: Using 'c' instead of 'b'
    return a + c;
}

/**
 * Calculates the product of two numbers
 * @param {number} a First number
 * @param {number} b Second number
 * @returns {number} The product of a and b
 */
function calculateProduct(a, b) {
    // BUG: Missing return statement
    a * b;
}

module.exports = {
    greet,
    calculateSum,
    calculateProduct
};
EOF
    
    # Add files to git
    git add package.json index.js utils.js
    git commit -m "Initial commit with buggy code" &> /dev/null
    
    echo -e "${GREEN}✓ Test repository setup complete${NC}"
}

# Function to start the Aider service
start_aider_service() {
    echo -e "\n${BLUE}Starting Aider service...${NC}"
    
    cd "$SERVICE_ROOT"
    
    # Check if service is already running
    if lsof -i:$PORT -t &>/dev/null; then
        echo -e "${YELLOW}Service already running on port $PORT...${NC}"
    else
        # Start service in background
        echo -e "${YELLOW}Starting service on port $PORT...${NC}"
        npm run dev > /tmp/aider-service-log.txt 2>&1 &
        SERVICE_PID=$!
        
        # Wait for service to start (up to 30 seconds)
        echo -e "${YELLOW}Waiting for service to start...${NC}"
        for i in {1..30}; do
            if curl -s http://localhost:$PORT/api/health > /dev/null; then
                echo -e "${GREEN}✓ Service started successfully${NC}"
                break
            fi
            
            if [ $i -eq 30 ]; then
                echo -e "${RED}✗ Service failed to start within 30 seconds${NC}"
                echo -e "${YELLOW}Service logs:${NC}"
                cat /tmp/aider-service-log.txt
                exit 1
            fi
            
            sleep 1
        done
    fi
}

# Function to test the health endpoint
test_health_endpoint() {
    echo -e "\n${BLUE}Testing health endpoint...${NC}"
    
    HEALTH_RESPONSE=$(curl -s http://localhost:$PORT/api/health)
    
    if [[ "$HEALTH_RESPONSE" == *"status"* && "$HEALTH_RESPONSE" == *"components"* ]]; then
        echo -e "${GREEN}✓ Health endpoint is OK${NC}"
    else
        echo -e "${RED}✗ Health endpoint returned unexpected response${NC}"
        echo "$HEALTH_RESPONSE"
        exit 1
    fi
}

# Function to create an Aider instance
create_aider_instance() {
    echo -e "\n${BLUE}Creating Aider instance...${NC}"
    
    THREAD_ID="e2e-test-$(date +%s)"
    
    RESPONSE=$(curl -s -X POST http://localhost:$PORT/api/instances \
        -H "Content-Type: application/json" \
        -d "{
            \"threadId\": \"$THREAD_ID\",
            \"openAIApiKey\": \"$OPENAI_API_KEY\",
            \"projectRoot\": \"$TEST_PROJECT_DIR\",
            \"model\": \"gpt-4\",
            \"autoCommit\": false
        }")
    
    if [[ "$RESPONSE" == *"RUNNING"* ]]; then
        echo -e "${GREEN}✓ Aider instance created successfully with thread ID: $THREAD_ID${NC}"
    else
        echo -e "${RED}✗ Failed to create Aider instance${NC}"
        echo "$RESPONSE"
        exit 1
    fi
    
    # Store thread ID for later use
    echo "$THREAD_ID" > /tmp/aider-thread-id.txt
}

# Function to wait for Aider instance to be ready
wait_for_aider_instance() {
    echo -e "\n${BLUE}Waiting for Aider instance to initialize...${NC}"
    
    THREAD_ID=$(cat /tmp/aider-thread-id.txt)
    
    # Wait for up to 30 seconds
    for i in {1..30}; do
        STATUS_RESPONSE=$(curl -s http://localhost:$PORT/api/instances/$THREAD_ID)
        
        if [[ "$STATUS_RESPONSE" == *"RUNNING"* ]]; then
            echo -e "${GREEN}✓ Aider instance is ready${NC}"
            break
        fi
        
        if [ $i -eq 30 ]; then
            echo -e "${RED}✗ Aider instance failed to initialize within 30 seconds${NC}"
            echo "$STATUS_RESPONSE"
            exit 1
        fi
        
        sleep 1
    done
}

# Function to send a fix command to Aider
send_fix_command() {
    echo -e "\n${BLUE}Sending command to fix JavaScript errors...${NC}"
    
    THREAD_ID=$(cat /tmp/aider-thread-id.txt)
    
    RESPONSE=$(curl -s -X POST http://localhost:$PORT/api/instances/$THREAD_ID/command \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"Please fix all bugs in utils.js. There are three bugs: 1) Using 'nme' instead of 'name' in the greet function, 2) Using 'c' instead of 'b' in the calculateSum function, and 3) Missing return statement in calculateProduct function.\"
        }")
    
    if [[ "$RESPONSE" == *"Command sent"* ]]; then
        echo -e "${GREEN}✓ Fix command sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send fix command${NC}"
        echo "$RESPONSE"
        exit 1
    fi
}

# Function to wait for the command to complete
wait_for_command_completion() {
    echo -e "\n${BLUE}Waiting for code fixes to complete...${NC}"
    
    THREAD_ID=$(cat /tmp/aider-thread-id.txt)
    
    # Wait a bit for LLM processing (at least 10 seconds)
    echo -e "${YELLOW}Waiting for initial LLM processing...${NC}"
    sleep 10
    
    # Debug info
    echo -e "${YELLOW}DEBUG: Test project directory: $TEST_PROJECT_DIR${NC}"
    echo -e "${YELLOW}DEBUG: Directory permissions:${NC}"
    ls -la "$TEST_PROJECT_DIR"
    echo -e "${YELLOW}DEBUG: Current utils.js content:${NC}"
    cat "$TEST_PROJECT_DIR/utils.js"
    
    # Make sure the test directory is writable
    chmod -R 777 "$TEST_PROJECT_DIR"
    
    # Now check every second for up to 2 minutes more
    for i in {1..120}; do
        if grep -q "name" "$TEST_PROJECT_DIR/utils.js" && grep -q "return a + b" "$TEST_PROJECT_DIR/utils.js"; then
            echo -e "${GREEN}✓ Changes detected in utils.js${NC}"
            break
        fi
            
        # Display file content periodically to see if it changes
        if [ $((i % 10)) -eq 0 ]; then
            echo -e "${YELLOW}DEBUG: Current utils.js content at ${i}s:${NC}"
            cat "$TEST_PROJECT_DIR/utils.js"
        fi
        
        echo -e "${YELLOW}Still waiting for file changes (${i}s)...${NC}"
        sleep 1
        
        if [ $i -eq 120 ]; then
            echo -e "${RED}✗ File changes not detected within 2 minutes${NC}"
            exit 1
        fi
    done
}

# Function to verify the fixes
verify_fixes() {
    echo -e "\n${BLUE}Verifying fixes in JavaScript files...${NC}"
    
    cd "$TEST_PROJECT_DIR"
    
    # Check if files exist
    if [ ! -f "utils.js" ]; then
        echo -e "${RED}✗ utils.js file not found${NC}"
        exit 1
    fi
    
    # Check for fixes using grep
    if grep -q "console.log(\"Hello, \" + name + \"!\");" utils.js; then
        echo -e "${GREEN}✓ Bug #1 fixed: 'nme' changed to 'name'${NC}"
    else
        echo -e "${RED}✗ Bug #1 not fixed${NC}"
        exit 1
    fi
    
    if grep -q "return a + b;" utils.js; then
        echo -e "${GREEN}✓ Bug #2 fixed: 'c' changed to 'b'${NC}"
    else
        echo -e "${RED}✗ Bug #2 not fixed${NC}"
        exit 1
    fi
    
    if grep -q "return a \* b;" utils.js; then
        echo -e "${GREEN}✓ Bug #3 fixed: Added return statement${NC}"
    else
        echo -e "${RED}✗ Bug #3 not fixed${NC}"
        exit 1
    fi
}

# Function to run the fixed code
run_fixed_code() {
    echo -e "\n${BLUE}Running the fixed code...${NC}"
    
    cd "$TEST_PROJECT_DIR"
    
    # Check if Node.js is installed
    if ! command_exists node; then
        echo -e "${YELLOW}Node.js not found, skipping code execution test${NC}"
        return
    fi
    
    # Run the code
    OUTPUT=$(node index.js 2>&1)
    
    # Check for successful output
    if [[ "$OUTPUT" == *"Greeting function result: Greeting completed"* && 
          "$OUTPUT" == *"Sum calculation result: 15"* && 
          "$OUTPUT" == *"Product calculation result: 50"* ]]; then
        echo -e "${GREEN}✓ Fixed code runs successfully${NC}"
    else
        echo -e "${RED}✗ Fixed code does not produce expected output${NC}"
        echo -e "${YELLOW}Output:${NC}"
        echo "$OUTPUT"
        exit 1
    fi
}

# Function to stop the Aider instance
stop_aider_instance() {
    echo -e "\n${BLUE}Stopping Aider instance...${NC}"
    
    THREAD_ID=$(cat /tmp/aider-thread-id.txt)
    
    RESPONSE=$(curl -s -X DELETE http://localhost:$PORT/api/instances/$THREAD_ID)
    
    if [[ "$RESPONSE" == *"HALTED"* ]]; then
        echo -e "${GREEN}✓ Aider instance stopped successfully${NC}"
    else
        echo -e "${RED}✗ Failed to stop Aider instance${NC}"
        echo "$RESPONSE"
        exit 1
    fi
}

# Function to clean up
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    
    # Remove temporary files
    rm -f /tmp/aider-thread-id.txt
    
    # Stop service if we started it
    if [ ! -z "$SERVICE_PID" ]; then
        kill $SERVICE_PID 2>/dev/null || true
        rm -f /tmp/aider-service-log.txt
    fi
    
    # Remove test project directory
    rm -rf "$TEST_PROJECT_DIR"
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Main execution with timeout
run_with_timeout() {
    # Set up trap to handle termination
    trap cleanup EXIT INT TERM
    
    # Start time
    START_TIME=$(date +%s)
    
    # Header
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "${BLUE}       End-to-End Test for Aider Command Interface        ${NC}"
    echo -e "${BLUE}==========================================================${NC}"
    
    # Load environment variables
    load_env_vars
    
    # Setup test repository
    setup_test_repo
    
    # Start Aider service
    start_aider_service
    
    # Test health endpoint
    test_health_endpoint
    
    # Create Aider instance
    create_aider_instance
    
    # Wait for instance to be ready
    wait_for_aider_instance
    
    # Send fix command
    send_fix_command
    
    # Wait for command to complete
    wait_for_command_completion
    
    # Verify fixes
    verify_fixes
    
    # Run fixed code
    run_fixed_code
    
    # Stop Aider instance
    stop_aider_instance
    
    # End time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    # Success message
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}       End-to-End Test Completed Successfully!            ${NC}"
    echo -e "${GREEN}       Total duration: ${DURATION} seconds                 ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
}

# Execute main function directly instead of using timeout
run_with_timeout
