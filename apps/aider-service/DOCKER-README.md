# Aider Service Docker Setup

This directory contains a Docker-based setup for the Aider service, allowing you to run Aider in an isolated environment without affecting your local system. The Docker setup exposes the Aider service on port 9876.

## Features

- Runs Aider service in a Docker container
- Uses MongoDB for persistent storage
- Isolates dependencies from your local system
- Automatically tests JavaScript typo fixing capabilities
- Follows MAGA Protocol for deployment

## Prerequisites

- Docker
- Docker Compose
- OpenAI API key

## Quick Start

1. **Set up environment variables**

   Create a `.env` file in the parent directory with:

   ```
   OPENAI_API_KEY=your_openai_api_key
   GH_TOKEN=your_github_token
   ```

2. **Run the deployment script**

   ```bash
   chmod +x deploy-docker.sh
   ./deploy-docker.sh
   ```

   This will build and start the Docker services.

3. **Run the test client**

   ```bash
   chmod +x test-client.sh
   ./test-client.sh
   ```

   This will test the Aider service by cloning the js-typo-test repository, fixing the typos, and verifying the changes.

## Services

- **MongoDB**: Runs on port 27018
- **Aider Service**: Runs on port 9876

## API Endpoints

- **Health Check**: `GET http://localhost:9876/api/health`
- **Create Instance**: `POST http://localhost:9876/api/instances`
- **Get Instance**: `GET http://localhost:9876/api/instances/:threadId`
- **Send Command**: `POST http://localhost:9876/api/instances/:threadId/command`
- **Stop Instance**: `DELETE http://localhost:9876/api/instances/:threadId`

## Example Usage

### Create an Aider instance

```bash
curl -X POST http://localhost:9876/api/instances \
  -H "Content-Type: application/json" \
  -d '{
    "threadId": "test-thread",
    "openAIApiKey": "your_openai_api_key",
    "projectRoot": "/path/to/your/project",
    "autoCommit": true
  }'
```

### Send a command to fix JavaScript typos

```bash
curl -X POST http://localhost:9876/api/instances/test-thread/command \
  -H "Content-Type: application/json" \
  -d '{
    "command": "Fix all JavaScript typos in this repository"
  }'
```

## Troubleshooting

- If you have issues with the ports, check if they are already in use and modify the `docker-compose.yml` file to use different ports.
- Make sure your OpenAI API key is correctly set in the `.env` file.
- Check the Docker logs with `docker-compose logs -f` to see any errors. 