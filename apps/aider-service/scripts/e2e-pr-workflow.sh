#!/bin/bash
# E2E Test Script for JavaScript Typo Fixing with PR Workflow
# This script demonstrates:
# 1. Cloning a repository with JavaScript typos
# 2. Using Aider to fix the typos
# 3. Creating a fork of the repository
# 4. Pushing the changes to the fork
# 5. Creating a pull request

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
TEST_DIR="/tmp/aider-pr-test-$(date +%s)"
API_URL="http://localhost:3100/api"
THREAD_ID="pr-test-$(date +%s)"
GITHUB_API="https://api.github.com"

# Default test repository (should contain JavaScript with typos)
# This should be a repository you have access to for testing
SOURCE_REPO="YOUR_USERNAME/js-typo-test"
FORK_NAME="js-typo-test-fix"

# Function to load environment variables
load_env_vars() {
    echo -e "${YELLOW}Loading environment variables...${NC}"
    
    # Try loading from service .env
    if [ -f "$SERVICE_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from service .env file...${NC}"
        export $(grep -v '^#' "$SERVICE_ROOT/.env" | grep -E 'OPENAI_API_KEY|MONGO_URI|PORT|GITHUB_TOKEN|GH_TOKEN' | xargs)
    fi
    
    # Try loading from project root .env if still not set
    if [ -z "$OPENAI_API_KEY" ] && [ -f "$PROJECT_ROOT/.env" ]; then
        echo -e "${YELLOW}Loading from project root .env file...${NC}"
        export $(grep -v '^#' "$PROJECT_ROOT/.env" | grep -E 'OPENAI_API_KEY|GH_TOKEN' | xargs)
    fi
    
    # Check for GitHub token - use GH_TOKEN if GITHUB_TOKEN not set
    if [ -z "$GITHUB_TOKEN" ] && [ -n "$GH_TOKEN" ]; then
        echo -e "${YELLOW}Using GH_TOKEN since GITHUB_TOKEN is not set${NC}"
        export GITHUB_TOKEN=$GH_TOKEN
    fi
    
    # Check for required variables
    if [ -z "$OPENAI_API_KEY" ]; then
        echo -e "${RED}Error: OPENAI_API_KEY is not set${NC}"
        exit 1
    fi
    
    if [ -z "$GITHUB_TOKEN" ]; then
        echo -e "${RED}Error: Neither GITHUB_TOKEN nor GH_TOKEN is set. This is required for forking and creating PRs${NC}"
        exit 1
    fi
    
    # Set defaults if not specified
    if [ -z "$PORT" ]; then
        export PORT=3100
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to clone the test repository
clone_repository() {
    echo -e "\n${BLUE}Cloning source repository...${NC}"
    
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    echo -e "${YELLOW}Cloning from https://github.com/${SOURCE_REPO}.git${NC}"
    git clone "https://github.com/${SOURCE_REPO}.git" .
    git config --local user.email "aider-test@example.com"
    git config --local user.name "Aider Test User"
    
    echo -e "${GREEN}✓ Repository cloned successfully${NC}"
}

# Function to check the health of the Aider service
check_service_health() {
    echo -e "\n${BLUE}Checking Aider service health...${NC}"
    
    HEALTH_RESPONSE=$(curl -s ${API_URL}/health)
    
    if [[ "$HEALTH_RESPONSE" == *"status"* && "$HEALTH_RESPONSE" == *"UP"* ]]; then
        echo -e "${GREEN}✓ Aider service is healthy${NC}"
    else
        echo -e "${RED}✗ Aider service health check failed${NC}"
        echo "$HEALTH_RESPONSE"
        exit 1
    fi
}

# Function to start an Aider instance
start_aider_instance() {
    echo -e "\n${BLUE}Starting Aider instance for test repository...${NC}"
    
    START_RESPONSE=$(curl -s -X POST "${API_URL}/instances" \
        -H "Content-Type: application/json" \
        -d "{
            \"threadId\": \"${THREAD_ID}\",
            \"openAIApiKey\": \"${OPENAI_API_KEY}\",
            \"githubToken\": \"${GITHUB_TOKEN}\",
            \"projectRoot\": \"${TEST_DIR}\",
            \"autoCommit\": false
        }")
    
    echo "Response: $START_RESPONSE"
    
    if [[ "$START_RESPONSE" == *"RUNNING"* ]]; then
        echo -e "${GREEN}✓ Aider instance started successfully with ID: $THREAD_ID${NC}"
    else
        echo -e "${RED}✗ Failed to start Aider instance${NC}"
        exit 1
    fi
    
    # Wait for Aider to initialize
    echo -e "${YELLOW}Waiting for Aider to initialize (10 seconds)...${NC}"
    sleep 10
}

# Function to send a fix command to Aider
send_fix_command() {
    echo -e "\n${BLUE}Sending command to fix JavaScript typos...${NC}"
    
    COMMAND_RESPONSE=$(curl -s -X POST "${API_URL}/instances/${THREAD_ID}/command" \
        -H "Content-Type: application/json" \
        -d "{
            \"command\": \"Find and fix all JavaScript typos in this repository. Make sure all variable references are correct and fix any syntax errors.\"
        }")
    
    if [[ "$COMMAND_RESPONSE" == *"Command sent"* ]]; then
        echo -e "${GREEN}✓ Fix command sent successfully${NC}"
    else
        echo -e "${RED}✗ Failed to send fix command${NC}"
        echo "$COMMAND_RESPONSE"
        exit 1
    fi
    
    # Wait for Aider to process (this might take a while)
    echo -e "${YELLOW}Waiting for Aider to process typo fixes (60 seconds)...${NC}"
    for i in {1..60}; do
        echo -n "."
        sleep 1
    done
    echo -e "\n${GREEN}✓ Waited for processing${NC}"
}

# Function to check for changes
verify_changes() {
    echo -e "\n${BLUE}Verifying changes...${NC}"
    
    cd "$TEST_DIR"
    
    # Check if any changes were made
    if git diff --quiet HEAD; then
        echo -e "${RED}✗ No changes detected${NC}"
        echo "This could mean either no typos were found or Aider didn't make any changes."
        # Continue anyway for testing purposes
    else
        echo -e "${GREEN}✓ Changes detected${NC}"
        echo "Changes made by Aider:"
        git diff
    fi
    
    # Commit changes if any
    if ! git diff --quiet; then
        echo -e "${YELLOW}Committing changes...${NC}"
        git add .
        git commit -m "Fix JavaScript typos with Aider"
        echo -e "${GREEN}✓ Changes committed${NC}"
    fi
}

# Function to create a fork using GitHub API
create_fork() {
    echo -e "\n${BLUE}Creating fork of the repository...${NC}"
    
    # Extract owner/repo
    REPO_OWNER=$(echo $SOURCE_REPO | cut -d/ -f1)
    REPO_NAME=$(echo $SOURCE_REPO | cut -d/ -f2)
    
    # First check if fork already exists
    FORK_CHECK=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "${GITHUB_API}/repos/${GITHUB_USERNAME}/${REPO_NAME}")
    
    if [[ "$FORK_CHECK" != *"Not Found"* && "$FORK_CHECK" == *"clone_url"* ]]; then
        echo -e "${YELLOW}Fork already exists, using existing fork${NC}"
        FORK_URL=$(echo $FORK_CHECK | grep -o '"clone_url":"[^"]*"' | head -1 | cut -d'"' -f4)
    else
        # Create the fork
        FORK_RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
            "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/forks" \
            -d "{\"name\":\"${FORK_NAME}\"}")
        
        if [[ "$FORK_RESPONSE" == *"full_name"* ]]; then
            echo -e "${GREEN}✓ Fork created successfully${NC}"
            FORK_URL=$(echo $FORK_RESPONSE | grep -o '"clone_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        else
            echo -e "${RED}✗ Failed to create fork${NC}"
            echo "$FORK_RESPONSE"
            exit 1
        fi
        
        # Wait for fork to be ready
        echo -e "${YELLOW}Waiting for fork to be ready (10 seconds)...${NC}"
        sleep 10
    fi
    
    echo "Fork URL: $FORK_URL"
}

# Function to push changes to the fork
push_to_fork() {
    echo -e "\n${BLUE}Pushing changes to fork...${NC}"
    
    cd "$TEST_DIR"
    
    # Get user info from GitHub
    USER_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "${GITHUB_API}/user")
    GITHUB_USERNAME=$(echo $USER_INFO | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$GITHUB_USERNAME" ]; then
        echo -e "${RED}✗ Failed to get GitHub username${NC}"
        exit 1
    fi
    
    # Add the fork as a remote and push
    git remote add fork "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
    git push -u fork main || git push -u fork master
    
    echo -e "${GREEN}✓ Changes pushed to fork successfully${NC}"
}

# Function to create a pull request
create_pull_request() {
    echo -e "\n${BLUE}Creating pull request...${NC}"
    
    # Extract owner/repo
    REPO_OWNER=$(echo $SOURCE_REPO | cut -d/ -f1)
    REPO_NAME=$(echo $SOURCE_REPO | cut -d/ -f2)
    
    # Get the current branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    
    # Create the PR
    PR_RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
        "${GITHUB_API}/repos/${REPO_OWNER}/${REPO_NAME}/pulls" \
        -d "{
            \"title\": \"Fix JavaScript typos with Aider\",
            \"body\": \"This PR fixes JavaScript typos automatically detected and corrected by Aider.\",
            \"head\": \"${GITHUB_USERNAME}:${CURRENT_BRANCH}\",
            \"base\": \"main\"
        }")
    
    if [[ "$PR_RESPONSE" == *"html_url"* ]]; then
        PR_URL=$(echo $PR_RESPONSE | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "${GREEN}✓ Pull request created successfully${NC}"
        echo "PR URL: $PR_URL"
    else
        echo -e "${RED}✗ Failed to create pull request${NC}"
        echo "$PR_RESPONSE"
        exit 1
    fi
}

# Function to stop Aider instance
stop_aider_instance() {
    echo -e "\n${BLUE}Stopping Aider instance...${NC}"
    
    STOP_RESPONSE=$(curl -s -X DELETE "${API_URL}/instances/${THREAD_ID}")
    
    if [[ "$STOP_RESPONSE" == *"HALTED"* ]]; then
        echo -e "${GREEN}✓ Aider instance stopped successfully${NC}"
    else
        echo -e "${RED}✗ Failed to stop Aider instance${NC}"
        echo "$STOP_RESPONSE"
    fi
}

# Function to clean up
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    
    # Remove test directory
    rm -rf "$TEST_DIR"
    
    echo -e "${GREEN}✓ Cleanup complete${NC}"
}

# Main function
main() {
    # Header
    echo -e "${BLUE}==========================================================${NC}"
    echo -e "${BLUE}    JavaScript Typo Fix & PR Workflow with Aider          ${NC}"
    echo -e "${BLUE}==========================================================${NC}"
    
    # Load environment variables
    load_env_vars
    
    # Get GitHub username interactively if not set
    if [ -z "$GITHUB_USERNAME" ]; then
        read -p "Enter your GitHub username: " GITHUB_USERNAME
        if [ -z "$GITHUB_USERNAME" ]; then
            echo -e "${RED}Error: GitHub username is required${NC}"
            exit 1
        fi
    fi
    
    # Get source repository interactively if using default
    if [ "$SOURCE_REPO" == "YOUR_USERNAME/js-typo-test" ]; then
        read -p "Enter source repository (format: owner/repo): " SOURCE_REPO
        if [ -z "$SOURCE_REPO" ]; then
            echo -e "${RED}Error: Source repository is required${NC}"
            exit 1
        fi
    fi
    
    # Run the workflow steps
    check_service_health
    clone_repository
    start_aider_instance
    send_fix_command
    verify_changes
    create_fork
    push_to_fork
    create_pull_request
    stop_aider_instance
    cleanup
    
    # Success message
    echo -e "\n${GREEN}==========================================================${NC}"
    echo -e "${GREEN}    Workflow Completed Successfully!                      ${NC}"
    echo -e "${GREEN}==========================================================${NC}"
}

# Run the main function
main 