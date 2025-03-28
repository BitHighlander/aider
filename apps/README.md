# Aider Web Apps

This directory contains web applications for Aider:

## aider-service

A Node.js/Express service that provides a REST API and WebSocket interface to the Aider CLI tool. It allows multiple Aider instances to be controlled and monitored through a web interface.

## aider-web-client-new

A Next.js web client that provides a modern, user-friendly interface for interacting with Aider. Features include:
- Viewing and managing Aider instances
- Real-time chat interface with Aider
- Status monitoring
- Command history

## Getting Started

### Running the Aider Service

```bash
cd aider/apps/aider-service
npm install
npm run dev
```

The service will be available at http://localhost:3100/api.

### Running the Web Client

```bash
cd aider/apps/aider-web-client-new
npm install
npm run dev
```

The web client will be available at http://localhost:3000.

When integrated with the Aider service, you can access the web client at http://localhost:3100/app. 