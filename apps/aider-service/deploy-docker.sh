#!/bin/bash
# MAGA Protocol: Deployment Script for Aider Service in Docker
# This script sets up and deploys the Aider service in a Docker container

set -e # Exit on error

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}    MAGA Protocol: Aider Service Docker Deployment      ${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo

# Check for required tools
check_requirements() {
  echo -e "${YELLOW}Checking requirements...${NC}"
  
  # Check for Docker
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
  fi
  
  # Check for Docker Compose
  if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
    exit 1
  fi
  
  # Check for required environment variables
  if [ -z "$OPENAI_API_KEY" ]; then
    if [ -f "../.env" ]; then
      export $(grep OPENAI_API_KEY ../.env | xargs)
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
      echo -e "${RED}OPENAI_API_KEY is not set. Please set it in the environment or in ../.env${NC}"
      exit 1
    fi
  fi
  
  # Check for MongoDB connection string
  if [ -z "$MONGO_CONNECTION" ]; then
    if [ -f "../.env" ]; then
      export $(grep MONGO_CONNECTION ../.env | xargs)
    fi
    
    if [ -z "$MONGO_CONNECTION" ]; then
      echo -e "${RED}MONGO_CONNECTION is not set. Please set it in the environment or in ../.env${NC}"
      exit 1
    fi
  fi
  
  echo -e "${GREEN}✓ All requirements satisfied${NC}"
}

# Build and start the services
deploy_services() {
  echo -e "\n${YELLOW}Building and starting Docker services...${NC}"
  
  # Build the images locally only
  echo -e "${YELLOW}Building Docker images locally...${NC}"
  docker-compose build --no-cache
  
  # Start the services
  echo -e "${YELLOW}Starting services...${NC}"
  docker-compose up -d
  
  echo -e "${GREEN}✓ Services started${NC}"
}

# Wait for services to be ready
wait_for_services() {
  echo -e "\n${YELLOW}Waiting for services to be ready...${NC}"
  
  # Wait for Aider Service to be ready
  echo -e "${YELLOW}Waiting for Aider Service...${NC}"
  for i in {1..30}; do
    if curl -s http://localhost:9876/api/health | grep -q "UP"; then
      echo -e "${GREEN}✓ Aider Service is ready${NC}"
      break
    fi
    
    if [ $i -eq 30 ]; then
      echo -e "${RED}Aider Service is not ready after 30 seconds${NC}"
      exit 1
    fi
    
    echo -n "."
    sleep 1
  done
}

# Show service status
show_status() {
  echo -e "\n${YELLOW}Service Status:${NC}"
  
  docker-compose ps
  
  # Show the health check
  echo -e "\n${YELLOW}Health Check:${NC}"
  curl -s http://localhost:9876/api/health | python3 -m json.tool || echo -e "${RED}Failed to get health check${NC}"
}

# Show usage information
show_usage() {
  echo -e "\n${YELLOW}Usage:${NC}"
  echo -e "  http://localhost:9876/api/health - Health check endpoint"
  echo -e "  http://localhost:9876/api/instances - Create an Aider instance"
  echo -e "  http://localhost:9876/api/instances/:threadId - Get instance status"
  echo -e "  http://localhost:9876/api/instances/:threadId/command - Send command to instance"
  
  echo -e "\n${YELLOW}Example:${NC}"
  echo -e "  curl -X POST http://localhost:9876/api/instances \\"
  echo -e "    -H \"Content-Type: application/json\" \\"
  echo -e "    -d '{\\"threadId\\": \\"test-thread\\", \\"openAIApiKey\\": \\"$OPENAI_API_KEY\\", \\"projectRoot\\": \\"/path/to/repo\\"}'"
}

# Main function
main() {
  check_requirements
  deploy_services
  wait_for_services
  show_status
  show_usage
  
  echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}    MAGA Protocol: Deployment Completed Successfully    ${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
}

# Run the main function
main 