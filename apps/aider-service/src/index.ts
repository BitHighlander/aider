import express from 'express';
import http from 'http';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import YAML from 'yamljs';
import swaggerUi from 'swagger-ui-express';
import * as OpenApiValidator from 'express-openapi-validator';
import { createProxyMiddleware } from 'http-proxy-middleware';

import { LoggingService } from './services/LoggingService';
import { AiderService } from './services/AiderService';
import createRouter from './api/router';

// Load environment variables from both root and local .env files
dotenv.config({ path: path.resolve(__dirname, '../../../.env') });
dotenv.config({ path: path.resolve(__dirname, '../.env') });

// Create express app
const app = express();
const PORT = process.env.PORT || 3100;
const NEXT_APP_PORT = process.env.NEXT_APP_PORT || 3000;

// Set up middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Create HTTP server
const server = http.createServer(app);

// Load OpenAPI specification
const apiSpec = path.join(__dirname, 'api/openapi.yaml');
const openApiDocument = YAML.load(apiSpec);

// Use MONGO_CONNECTION environment variable if available, fallback to MONGO_URI
const mongoConnectionString = process.env.MONGO_CONNECTION || process.env.MONGO_URI;
if (mongoConnectionString) {
  console.log('MongoDB connection string found');
} else {
  console.warn('No MongoDB connection string found in environment variables');
}

// Initialize services
const loggingService = new LoggingService(server);
const aiderService = new AiderService(loggingService, mongoConnectionString);

// Set up Swagger UI
app.use('/docs', swaggerUi.serve, swaggerUi.setup(openApiDocument));

// Serve OpenAPI spec in JSON format
app.get('/openapi.json', (req, res) => {
  res.json(openApiDocument);
});

// Set up API validation middleware
app.use(
  OpenApiValidator.middleware({
    apiSpec,
    validateRequests: true,
    validateResponses: true,
  })
);

// Set up API routes
app.use('/api', createRouter(aiderService));

// Proxy requests to the Next.js app
app.use(['/', '/app', '/_next', '/favicon.ico', '/static'], createProxyMiddleware({
  target: `http://localhost:${NEXT_APP_PORT}`,
  changeOrigin: true,
  ws: true,
  pathRewrite: {
    '^/app': '', // Remove the '/app' prefix when forwarding to Next.js
    '^/$': ''    // Handle root path
  },
  // @ts-ignore - type definitions for http-proxy-middleware are not fully compatible
  onProxyReq: (proxyReq: any, req: any, res: any) => {
    // Modify the origin header to avoid CORS issues
    proxyReq.setHeader('Origin', `http://localhost:${NEXT_APP_PORT}`);
    console.log(`Proxying request: ${req.method} ${req.url} to http://localhost:${NEXT_APP_PORT}${req.url.replace(/^\/app/, '')}`);
  },
  // @ts-ignore - type definitions for http-proxy-middleware are not fully compatible
  onError: (err: Error, req: express.Request, res: express.Response) => {
    console.error('Proxy error:', err);
    res.status(500).send(`Next.js app is not running. Please start it with "npm run dev" in the aider-web-client-new directory. Error: ${err.message}`);
  },
  logLevel: 'debug'
}));

// Error handling middleware
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  // Handle validation errors
  if (err.status === 400) {
    return res.status(400).json({
      error: err.message,
      errors: err.errors
    });
  }
  
  // Handle other errors
  console.error('Unhandled error:', err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal Server Error'
  });
});

// Start server
server.listen(PORT, async () => {
  console.log(`Aider Service running on port ${PORT}`);
  console.log(`API documentation available at http://localhost:${PORT}/docs`);
  console.log(`Web client available at http://localhost:${PORT}/app`);
  console.log(`NOTE: You must start the Next.js app separately with "npm run dev" in the aider-web-client-new directory`);
  
  // Restore previous Aider states
  try {
    await aiderService.restoreStates();
    console.log('Previous Aider instances restored from database');
  } catch (error) {
    console.error('Error restoring Aider states:', error);
  }
});

// Handle graceful shutdown
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

async function shutdown() {
  console.log('Shutting down Aider Service...');
  // Get all instances and try to stop them gracefully
  const instances = aiderService.getAllStatuses();
  
  for (const [threadId] of instances) {
    try {
      await aiderService.stopAider(threadId);
      console.log(`Stopped Aider instance ${threadId}`);
    } catch (error) {
      console.error(`Error stopping Aider instance ${threadId}:`, error);
    }
  }
  
  console.log('Shutdown complete');
  process.exit(0);
}
