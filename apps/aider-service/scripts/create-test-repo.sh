#!/bin/bash
# Script to create a test repository with JavaScript typos
# This creates a GitHub repository with JavaScript files containing deliberate typos
# for testing the Aider PR workflow

set -e # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_NAME="js-typo-test"
LOCAL_DIR="/tmp/${REPO_NAME}"
GITHUB_API="https://api.github.com"

# Check for GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    # Try using GH_TOKEN if GITHUB_TOKEN is not set
    if [ -n "$GH_TOKEN" ]; then
        echo -e "${YELLOW}Using GH_TOKEN since GITHUB_TOKEN is not set${NC}"
        export GITHUB_TOKEN=$GH_TOKEN
    else
        echo -e "${RED}Error: Neither GITHUB_TOKEN nor GH_TOKEN environment variables are set${NC}"
        echo "Please set one of them with: export GITHUB_TOKEN=your_token or export GH_TOKEN=your_token"
        exit 1
    fi
fi

# Get GitHub username
if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${YELLOW}GitHub username not set. Fetching from API...${NC}"
    USER_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "${GITHUB_API}/user")
    GITHUB_USERNAME=$(echo $USER_INFO | grep -o '"login":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$GITHUB_USERNAME" ]; then
        echo -e "${RED}Error: Could not determine GitHub username${NC}"
        echo "Please set it manually with: export GITHUB_USERNAME=your_username"
        exit 1
    fi
    
    echo -e "${GREEN}GitHub username: ${GITHUB_USERNAME}${NC}"
fi

# Create local directory
echo -e "\n${BLUE}Creating local repository...${NC}"
mkdir -p $LOCAL_DIR
cd $LOCAL_DIR

# Initialize git repository
git init
git config --local user.email "${GITHUB_USERNAME}@users.noreply.github.com"
git config --local user.name "$GITHUB_USERNAME"

# Create README.md
cat > README.md << 'EOF'
# JavaScript Typo Test Repository

This repository contains JavaScript files with deliberate typos for testing Aider's ability to detect and fix them.

## Files

- `utils.js` - Utility functions with typos
- `app.js` - Main application file importing utils.js
- `math.js` - Mathematical functions with syntax errors
EOF

# Create package.json
cat > package.json << 'EOF'
{
  "name": "js-typo-test",
  "version": "1.0.0",
  "description": "Test repository with JavaScript typos for Aider testing",
  "main": "app.js",
  "scripts": {
    "test": "node app.js",
    "start": "node app.js"
  },
  "author": "Aider Test",
  "license": "MIT"
}
EOF

# Create utils.js with deliberate typos
cat > utils.js << 'EOF'
/**
 * Utility functions with deliberate typos for testing
 */

// TYPO: 'mesage' should be 'message'
function logMessge(mesage) {
  console.log(mesage);
  return true;
}

// TYPO: Missing parenthesis in function call
function processData(data) {
  if (!data {
    return null;
  }
  
  // TYPO: Using 'dat' instead of 'data'
  return dat.toString();
}

// TYPO: 'concate' should be 'concat'
function concateStrings(str1, str2) {
  // TYPO: Using '+' instead of ',' in console.log
  console.log("Concatenating strings" + str1 + "and" + str2);
  return str1 + str2;
}

module.exports = {
  logMessge,
  processData,
  concateStrings
};
EOF

# Create app.js that imports utils.js
cat > app.js << 'EOF'
const utils = require('./utils');
const math = require('./math');

// TYPO: 'messge' should be 'message'
const messge = "Hello, world!";

// Try to use the logging function
try {
  // TYPO: Function name misspelled - 'logMessge' instead of 'logMessage'
  utils.logMessge(messge);
} catch (error) {
  console.error("Error in logging:", error.message);
}

// Try to use the process function with bad data
try {
  const result = utils.processData(null);
  console.log("Process result:", result);
} catch (error) {
  console.error("Error in processing:", error.message);
}

// Try to concatenate strings
try {
  // TYPO: Function name misspelled - 'concateStrings' instead of 'concatenateStrings'
  const combined = utils.concateStrings("Hello", "World");
  console.log("Combined:", combined);
} catch (error) {
  console.error("Error in concatenation:", error.message);
}

// Try to use math functions
try {
  const sum = math.calculateSum(5, 10);
  console.log("Sum:", sum);
  
  const product = math.calculateProduct(5, 10);
  console.log("Product:", product);
} catch (error) {
  console.error("Error in math calculation:", error.message);
}
EOF

# Create math.js with syntax errors
cat > math.js << 'EOF'
/**
 * Math utility functions with deliberate errors
 */

// TYPO: Using 'numbr' instead of 'number'
function isPositive(numbr) {
  // TYPO: Using '=' instead of '==' for comparison
  return numbr = 0;
}

// TYPO: Missing comma between parameters
function calculateSum(a b) {
  return a + b;
}

// TYPO: Using '*' instead of '+' in function name
function calculate*Product(a, b) {
  // TYPO: Missing return statement
  a * b;
}

// TYPO: Incorrect export syntax
module.exports = {
  isPositive
  calculateSum,
  calculate*Product
}
EOF

# Add files to git
git add README.md package.json utils.js app.js math.js
git commit -m "Initial commit with JavaScript files containing deliberate typos"

# Check if repository already exists
REPO_CHECK=$(curl -s -I -H "Authorization: token $GITHUB_TOKEN" \
  "${GITHUB_API}/repos/${GITHUB_USERNAME}/${REPO_NAME}")

if [[ "$REPO_CHECK" == *"Status: 200"* ]]; then
  echo -e "${YELLOW}Repository ${GITHUB_USERNAME}/${REPO_NAME} already exists${NC}"
  echo -e "${YELLOW}Do you want to delete and recreate it? (y/N)${NC}"
  read -r CONFIRM
  
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deleting existing repository...${NC}"
    curl -s -X DELETE -H "Authorization: token $GITHUB_TOKEN" \
      "${GITHUB_API}/repos/${GITHUB_USERNAME}/${REPO_NAME}"
    
    # Small delay to ensure deletion is processed
    sleep 2
  else
    echo -e "${YELLOW}Using existing repository. Local changes will be pushed.${NC}"
    # Set remote origin
    git remote add origin "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
    git push -f origin master || git push -f origin main
    
    echo -e "\n${GREEN}Test repository updated: https://github.com/${GITHUB_USERNAME}/${REPO_NAME}${NC}"
    echo -e "${GREEN}Use this repository path for the PR workflow script: ${GITHUB_USERNAME}/${REPO_NAME}${NC}"
    exit 0
  fi
fi

# Create repository on GitHub
echo -e "\n${BLUE}Creating repository on GitHub...${NC}"
CREATE_RESPONSE=$(curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" \
  "${GITHUB_API}/user/repos" -d "{
  \"name\": \"${REPO_NAME}\",
  \"description\": \"Test repository with JavaScript typos for Aider testing\",
  \"private\": false,
  \"has_issues\": true,
  \"has_projects\": false,
  \"has_wiki\": false
}")

if [[ "$CREATE_RESPONSE" == *"html_url"* ]]; then
  REPO_URL=$(echo $CREATE_RESPONSE | grep -o '"html_url":"[^"]*"' | head -1 | cut -d'"' -f4)
  echo -e "${GREEN}Repository created: ${REPO_URL}${NC}"
else
  echo -e "${RED}Failed to create repository${NC}"
  echo "$CREATE_RESPONSE"
  exit 1
fi

# Push to GitHub
git remote add origin "https://${GITHUB_USERNAME}:${GITHUB_TOKEN}@github.com/${GITHUB_USERNAME}/${REPO_NAME}.git"
git push -u origin master || git push -u origin main

echo -e "\n${GREEN}Test repository created: https://github.com/${GITHUB_USERNAME}/${REPO_NAME}${NC}"
echo -e "${GREEN}Use this repository path for the PR workflow script: ${GITHUB_USERNAME}/${REPO_NAME}${NC}" 