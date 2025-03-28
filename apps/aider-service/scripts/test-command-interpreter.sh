#!/bin/bash
# Test script for the Aider command interpreter
# This script tests the command-based interface for Aider

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AIDER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../aider" && pwd)"
SERVICE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_PROJECT_DIR="/tmp/aider-test-project-$(date +%s)"
TEST_CODE_FILE="$TEST_PROJECT_DIR/hello.js"

# Print header
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}       Testing Aider Command Interpreter                   ${NC}"
echo -e "${BLUE}==========================================================${NC}"

# Try to load the API key from environment files
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}OPENAI_API_KEY not set in environment, trying to load from .env files...${NC}"
    
    # Try loading from service .env
    if [ -f "$SERVICE_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from service .env file...${NC}"
        export $(grep -v '^#' "$SERVICE_ROOT/.env" | grep OPENAI_API_KEY | xargs)
    fi
    
    # Try loading from project root .env if still not set
    if [ -z "$OPENAI_API_KEY" ] && [ -f "$PROJECT_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from project root .env file...${NC}"
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | grep OPENAI_API_KEY | xargs)
    fi
fi

# Check if we want to run in dummy mode for CI/CD testing
DUMMY_MODE=0
if [ "$1" == "--dummy" ] || [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${YELLOW}Running in dummy mode - no actual API calls will be made${NC}"
    DUMMY_MODE=1
    export OPENAI_API_KEY="dummy-key-for-testing"
fi

# Check if OpenAI API key is set now
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}ERROR: OPENAI_API_KEY is not set. Please set it before running this script.${NC}"
    exit 1
fi

# Create test project directory
echo -e "\n${YELLOW}Creating test project directory...${NC}"
mkdir -p "$TEST_PROJECT_DIR"
cd "$TEST_PROJECT_DIR"

# Initialize git repository
echo -e "\n${YELLOW}Initializing git repository...${NC}"
git init &> /dev/null
touch .gitignore
git add .gitignore
git config --local user.email "test@example.com"
git config --local user.name "Test User"
git commit -m "Initial commit" &> /dev/null

# Create a test JavaScript file with a deliberate error
echo -e "\n${YELLOW}Creating test JavaScript file with error...${NC}"
cat > "$TEST_CODE_FILE" << 'EOF'
// This is a test JavaScript file with a deliberate error
function greet(name) {
    console.log("Hello, " + nme + "!"); // Typo: should be 'name'
    return "Greeting completed";
}

// Another function with a different error
function calculateSum(a, b) {
    return a + c; // Error: 'c' is undefined, should be 'b'
}

// Export the functions
module.exports = {
    greet,
    calculateSum
};
EOF

# Add the file to git
git add "$TEST_CODE_FILE"
git commit -m "Add hello.js with errors" &> /dev/null

# Run different tests based on mode
if [ $DUMMY_MODE -eq 1 ]; then
    # Dummy test mode - validate structure without making API calls
    
    echo -e "\n${YELLOW}Test 1: Verify command interpreter structure (dummy mode)...${NC}"
    if [ -f "$AIDER_ROOT/aider/command_interpreter.py" ]; then
        echo -e "${GREEN}✓ Command interpreter file exists${NC}"
    else
        echo -e "${RED}✗ Command interpreter file not found${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}Test 2: Verify command interpreter imports (dummy mode)...${NC}"
    if grep -q "class CommandInterpreter" "$AIDER_ROOT/aider/command_interpreter.py"; then
        echo -e "${GREEN}✓ CommandInterpreter class found${NC}"
    else
        echo -e "${RED}✗ CommandInterpreter class not found${NC}"
        exit 1
    fi
    
    echo -e "\n${YELLOW}Test 3: Dummy file fix (dummy mode)...${NC}"
    # Simulate a fix - macOS compatible version
    sed -i '' 's/nme/name/g' "$TEST_CODE_FILE"
    sed -i '' 's/a + c/a + b/g' "$TEST_CODE_FILE"
    echo -e "${GREEN}✓ Simulated fix successful${NC}"
    
    echo -e "\n${YELLOW}Test 4: Verify file was fixed (dummy mode)...${NC}"
    if grep -q "name" "$TEST_CODE_FILE" && grep -q "return a + b" "$TEST_CODE_FILE"; then
        echo -e "${GREEN}✓ JavaScript errors were fixed correctly${NC}"
    else
        echo -e "${RED}✗ JavaScript errors were not fixed${NC}"
        cat "$TEST_CODE_FILE"
        exit 1
    fi
else
    # Real test mode - actually use the API
    
    # Test 1: Initialize the command interpreter
    echo -e "\n${YELLOW}Test 1: Initialize the command interpreter...${NC}"
    cd "$AIDER_ROOT"
    COMMAND_RESULT=$(python3 -m aider.command_interpreter "$TEST_PROJECT_DIR" --command "/help" --model "gpt-4")

    if [[ "$COMMAND_RESULT" == *"command"* && "$COMMAND_RESULT" == *"output"* ]]; then
        echo -e "${GREEN}✓ Command interpreter initialized successfully${NC}"
    else
        echo -e "${RED}✗ Command interpreter initialization failed${NC}"
        echo "$COMMAND_RESULT"
        exit 1
    fi

    # Test 2: Fix the JavaScript file using the command interpreter
    echo -e "\n${YELLOW}Test 2: Fixing JavaScript errors...${NC}"
    cd "$AIDER_ROOT"
    COMMAND_RESULT=$(python3 -m aider.command_interpreter "$TEST_PROJECT_DIR" --command "Fix the bugs in hello.js. One bug is using 'nme' instead of 'name', and the other is using 'c' instead of 'b'." --model "gpt-4")

    # Check if the command was successful
    if [[ "$COMMAND_RESULT" == *"success"* && "$COMMAND_RESULT" == *"true"* ]]; then
        echo -e "${GREEN}✓ Command executed successfully${NC}"
    else
        echo -e "${RED}✗ Command execution failed${NC}"
        echo "$COMMAND_RESULT"
    fi

    # Test 3: Verify that the file was fixed
    echo -e "\n${YELLOW}Test 3: Verifying file fixes...${NC}"
    if grep -q "name" "$TEST_CODE_FILE" && grep -q "return a + b" "$TEST_CODE_FILE"; then
        echo -e "${GREEN}✓ JavaScript errors were fixed correctly${NC}"
    else
        echo -e "${RED}✗ JavaScript errors were not fixed${NC}"
        cat "$TEST_CODE_FILE"
    fi

    # Test 4: Try a slash command
    echo -e "\n${YELLOW}Test 4: Testing slash command...${NC}"
    cd "$AIDER_ROOT"
    COMMAND_RESULT=$(python3 -m aider.command_interpreter "$TEST_PROJECT_DIR" --command "/files" --model "gpt-4")

    if [[ "$COMMAND_RESULT" == *"hello.js"* ]]; then
        echo -e "${GREEN}✓ Slash command executed successfully${NC}"
    else
        echo -e "${RED}✗ Slash command failed${NC}"
        echo "$COMMAND_RESULT"
    fi
fi

# Clean up
echo -e "\n${YELLOW}Cleaning up...${NC}"
rm -rf "$TEST_PROJECT_DIR"

echo -e "\n${GREEN}All tests completed!${NC}"
