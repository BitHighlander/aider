#!/bin/bash
# Direct test for Aider command interpreter
# This script directly tests the command interpreter with full logging

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
TEST_PROJECT_DIR="/tmp/aider-direct-test-$(date +%s)"
PYTHON_PATH=$(which python3)

# Print header
echo -e "${BLUE}==========================================================${NC}"
echo -e "${BLUE}       Direct Test for Aider Command Interface            ${NC}"
echo -e "${BLUE}==========================================================${NC}"

# Function to load environment variables
load_env_vars() {
    echo -e "${YELLOW}Loading environment variables...${NC}"
    
    # Try loading from service .env
    if [ -f "$SERVICE_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from service .env file...${NC}"
        export $(grep -v '^#' "$SERVICE_ROOT/.env" | grep OPENAI_API_KEY | xargs)
    fi
    
    # Check if OpenAI API key is set
    if [ -z "$OPENAI_API_KEY" ]; then
        echo -e "${RED}ERROR: OPENAI_API_KEY is not set. Please set it before running this script.${NC}"
        exit 1
    fi
}

# Function to setup test repository
setup_test_repo() {
    echo -e "\n${BLUE}Setting up test repository...${NC}"
    
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Initialize git repository
    echo -e "${YELLOW}Initializing git repository...${NC}"
    git init
    git config --local user.email "test@example.com"
    git config --local user.name "Test User"
    
    # Create a test JavaScript file with deliberate errors
    echo -e "${YELLOW}Creating JavaScript file with errors...${NC}"
    
    cat > hello.js << 'EOF'
// This is a test JavaScript file with deliberate errors

/**
 * Greets a person by name
 */
function greet(name) {
    // BUG: Using 'nme' instead of 'name'
    console.log("Hello, " + nme + "!");
    return "Greeting completed";
}

/**
 * Calculates the sum of two numbers
 */
function calculateSum(a, b) {
    // BUG: Using 'c' instead of 'b'
    return a + c;
}

/**
 * Calculates the product of two numbers
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
    
    # Add file to git
    git add hello.js
    git commit -m "Add hello.js with errors"
    
    echo -e "${GREEN}✓ Test repository setup complete${NC}"
    echo -e "${YELLOW}Test repository path: ${TEST_PROJECT_DIR}${NC}"
}

# Function to directly run the command interpreter
run_command_interpreter() {
    echo -e "\n${BLUE}Running Aider command interpreter directly...${NC}"
    
    cd "$AIDER_ROOT"
    
    # Run with full logging enabled
    echo -e "${YELLOW}Command: $PYTHON_PATH -m aider.command_interpreter \"$TEST_PROJECT_DIR\" --command \"Fix the bugs in hello.js\" --model \"gpt-4\" --verbose${NC}"
    echo -e "${YELLOW}====================== BEGIN AIDER OUTPUT ======================${NC}"
    
    OPENAI_API_KEY=$OPENAI_API_KEY $PYTHON_PATH -m aider.command_interpreter "$TEST_PROJECT_DIR" \
        --command "Fix the bugs in hello.js. There are three bugs: 1) Using 'nme' instead of 'name' in the greet function, 2) Using 'c' instead of 'b' in the calculateSum function, and 3) Missing return statement in calculateProduct function." \
        --model "gpt-4" \
        --verbose
    
    echo -e "${YELLOW}====================== END AIDER OUTPUT ======================${NC}"
}

# Function to verify the fixes
verify_fixes() {
    echo -e "\n${BLUE}Verifying fixes in hello.js...${NC}"
    
    cd "$TEST_PROJECT_DIR"
    
    echo -e "${YELLOW}Current content of hello.js:${NC}"
    cat hello.js
    
    # Check for fixes using grep
    if grep -q "console.log(\"Hello, \" + name + \"!\");" hello.js; then
        echo -e "${GREEN}✓ Bug #1 fixed: 'nme' changed to 'name'${NC}"
    else
        echo -e "${RED}✗ Bug #1 not fixed${NC}"
    fi
    
    if grep -q "return a + b;" hello.js; then
        echo -e "${GREEN}✓ Bug #2 fixed: 'c' changed to 'b'${NC}"
    else
        echo -e "${RED}✗ Bug #2 not fixed${NC}"
    fi
    
    if grep -q "return a \* b;" hello.js; then
        echo -e "${GREEN}✓ Bug #3 fixed: Added return statement${NC}"
    else
        echo -e "${RED}✗ Bug #3 not fixed${NC}"
    fi
}

# Function to run the fixed code
run_fixed_code() {
    echo -e "\n${BLUE}Running the fixed code...${NC}"
    
    cd "$TEST_PROJECT_DIR"
    
    # Create a test script to use the module
    cat > test.js << 'EOF'
const utils = require('./hello');

try {
    console.log("Testing greet function:");
    const greeting = utils.greet("World");
    console.log(`Result: ${greeting}`);
} catch (error) {
    console.error("Error in greet function:", error.message);
}

try {
    console.log("\nTesting calculateSum function:");
    const sum = utils.calculateSum(5, 10);
    console.log(`Result: 5 + 10 = ${sum}`);
} catch (error) {
    console.error("Error in calculateSum function:", error.message);
}

try {
    console.log("\nTesting calculateProduct function:");
    const product = utils.calculateProduct(5, 10);
    console.log(`Result: 5 * 10 = ${product}`);
} catch (error) {
    console.error("Error in calculateProduct function:", error.message);
}
EOF
    
    echo -e "${YELLOW}Running node test.js:${NC}"
    node test.js
}

# Function for cleanup
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    
    # Ask if user wants to keep the test directory
    read -p "Do you want to keep the test directory? (y/n): " keep_dir
    
    if [[ "$keep_dir" != "y" ]]; then
        rm -rf "$TEST_PROJECT_DIR"
        echo -e "${GREEN}✓ Test directory removed${NC}"
    else
        echo -e "${YELLOW}Test directory kept at: ${TEST_PROJECT_DIR}${NC}"
    fi
}

# Main execution
main() {
    # Set up trap to handle cleanup on exit
    trap cleanup EXIT
    
    # Load environment variables
    load_env_vars
    
    # Setup test repository
    setup_test_repo
    
    # Run command interpreter directly
    run_command_interpreter
    
    # Verify fixes
    verify_fixes
    
    # Run the fixed code if available
    if grep -q "return a \* b;" "$TEST_PROJECT_DIR/hello.js"; then
        run_fixed_code
    fi
    
    # Success message
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}       Direct Test Completed                              ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
}

# Run main function
main
