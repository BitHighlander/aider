# Pioneer Aider Service

A service wrapper for Aider AI integration in the Pioneer Desktop project.

## Architecture

The Aider Service is designed to wrap the Aider AI code assistant to provide a RESTful API and WebSocket-based logging system. The service manages the lifecycle of Aider instances, including starting, stopping, and status monitoring.

### Key Components

1. **AiderService**: Core service to manage Aider processes
   - Handles process lifecycle (start/stop)
   - Manages state transitions (NOT_CONFIGURED → RUNNING → HALTED)
   - Provides diagnostic information

2. **API Layer**: REST API endpoints for Eliza agents
   - `/api/start` - Start a new Aider instance
   - `/api/stop/:threadId` - Stop an existing instance
   - `/api/status/:threadId` - Get status of specific instance
   - `/api/status` - Get all instance statuses
   - `/api/command/:threadId` - Send command to an instance

3. **WebSocket Logging**: Real-time logging system
   - Per-thread log streams
   - Status updates and error reporting
   - Client subscription management

## Getting Started

### Prerequisites

- Node.js 16+
- TypeScript
- Python 3.9+ (for Aider)
- Valid OpenAI API key

### Installation

1. Install dependencies:
   ```bash
   cd apps/aider-service
   npm install
   ```

2. Build the TypeScript code:
   ```bash
   npm run build
   ```

### Running the Service

```bash
npm run start
```

For development with auto-reload:
```bash
npm run dev
```

## API Usage

### Start an Aider Instance

```bash
curl -X POST http://localhost:3100/api/start \
  -H "Content-Type: application/json" \
  -d '{
    "threadId": "unique-thread-id",
    "config": {
      "openAiApiKey": "sk-your-api-key",
      "workingDirectory": "/path/to/project",
      "modelName": "gpt-4-turbo"
    }
  }'
```

### Stop an Aider Instance

```bash
curl -X POST http://localhost:3100/api/stop/unique-thread-id
```

### Get Status

```bash
curl http://localhost:3100/api/status/unique-thread-id
```

### Send a Command

```bash
curl -X POST http://localhost:3100/api/command/unique-thread-id \
  -H "Content-Type: application/json" \
  -d '{
    "command": "Add a login function to auth.js"
  }'
```

## WebSocket Logging

Connect to the WebSocket endpoint to receive real-time logs:

```javascript
const ws = new WebSocket('ws://localhost:3100?threadId=unique-thread-id');

ws.onmessage = (event) => {
  const log = JSON.parse(event.data);
  console.log(`[${log.level}] ${log.timestamp}: ${log.message}`);
};
```

## Sprint Plan

### Sprint 1: Core Integration & Structure (Current)
- [x] Set up Aider as Git submodule
- [x] Design service architecture
- [x] Create core service components
- [x] Implement basic API endpoints
- [x] Implement WebSocket logging
- [ ] Basic state management & diagnostics
- [ ] Initial integration testing

### Sprint 2: Enhanced Features
- [ ] Multi-project configuration management
- [ ] Persistent project storage
- [ ] Enhanced error handling and recovery
- [ ] Better output parsing and processing
- [ ] Authentication and security
- [ ] Comprehensive documentation

## Next Steps

1. Complete integration with the Pioneer Desktop frontend
2. Expand CLI capabilities to interact with the service
3. Add authentication and security features
4. Enhance logging and diagnostic capabilities
5. Create a dashboard for monitoring Aider instances
