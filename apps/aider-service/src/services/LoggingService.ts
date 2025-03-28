import WebSocket from 'ws';
import { v4 as uuidv4 } from 'uuid';

/**
 * Log message structure
 */
export interface LogMessage {
  id: string;
  timestamp: Date;
  threadId: string;
  content: string;
  level: 'info' | 'error' | 'debug';
}

/**
 * Service to handle logging and real-time communication via WebSockets
 */
export class LoggingService {
  private wss: WebSocket.Server;
  private clients: Map<WebSocket, {
    threadId?: string;
    lastActivity: Date;
  }> = new Map();

  // In-memory log buffer (could be replaced with a persistent store)
  private messageBuffer: Map<string, LogMessage[]> = new Map();
  private bufferSize = 500; // Max messages per thread

  /**
   * Create a new LoggingService
   * @param server HTTP server to attach WebSocket server to
   */
  constructor(server: any) {
    // Initialize WebSocket server
    this.wss = new WebSocket.Server({ server });
    
    // Setup connection handling
    this.wss.on('connection', this.handleConnection.bind(this));
    
    // Set up periodic check for inactive clients
    setInterval(this.cleanupInactiveClients.bind(this), 60000);
    
    console.log('LoggingService initialized with WebSocket server');
  }

  /**
   * Handle new WebSocket connections
   * @param ws WebSocket connection
   */
  private handleConnection(ws: WebSocket): void {
    // Register the new client
    this.clients.set(ws, {
      lastActivity: new Date()
    });
    
    console.log(`New WebSocket connection established, total clients: ${this.clients.size}`);
    
    // Set up message handler for client commands
    ws.on('message', (message: string) => {
      try {
        const data = JSON.parse(message);
        this.handleClientMessage(ws, data);
      } catch (error) {
        ws.send(JSON.stringify({
          type: 'error',
          message: 'Invalid message format'
        }));
      }
    });
    
    // Handle disconnection
    ws.on('close', () => {
      this.clients.delete(ws);
      console.log(`WebSocket connection closed, remaining clients: ${this.clients.size}`);
    });
    
    // Send initial welcome message
    ws.send(JSON.stringify({
      type: 'info',
      message: 'Connected to Aider Logging Service'
    }));
  }
  
  /**
   * Handle messages from WebSocket clients
   * @param ws WebSocket connection
   * @param data Message data
   */
  private handleClientMessage(ws: WebSocket, data: any): void {
    // Update last activity time
    const client = this.clients.get(ws);
    if (!client) return;
    
    client.lastActivity = new Date();
    
    // Handle subscription to thread
    if (data.type === 'subscribe' && data.threadId) {
      client.threadId = data.threadId;
      console.log(`Client subscribed to thread: ${data.threadId}`);
      
      // Send buffer of messages for this thread
      const messages = this.messageBuffer.get(data.threadId) || [];
      if (messages.length > 0) {
        ws.send(JSON.stringify({
          type: 'history',
          threadId: data.threadId,
          messages
        }));
      }
    }
    
    // Handle unsubscribe
    if (data.type === 'unsubscribe') {
      client.threadId = undefined;
      console.log('Client unsubscribed from thread');
    }
  }

  /**
   * Broadcast a log message to all clients subscribed to a thread
   * @param threadId Thread ID to broadcast to
   * @param content Message content
   * @param level Message level (default: 'info')
   */
  public broadcastLog(threadId: string, content: string, level: 'info' | 'error' | 'debug' = 'info'): void {
    const message: LogMessage = {
      id: uuidv4(),
      timestamp: new Date(),
      threadId,
      content,
      level
    };
    
    // Add to buffer
    this.addToBuffer(threadId, message);
    
    // Convert to string once
    const messageStr = JSON.stringify({
      type: 'log',
      message
    });
    
    // Send to all clients subscribed to this thread
    this.clients.forEach((client, ws) => {
      if (client.threadId === threadId && ws.readyState === WebSocket.OPEN) {
        ws.send(messageStr);
      }
    });
  }
  
  /**
   * Add a message to the buffer for a thread
   * @param threadId Thread ID
   * @param message Log message
   */
  private addToBuffer(threadId: string, message: LogMessage): void {
    // Get or create buffer for this thread
    const threadBuffer = this.messageBuffer.get(threadId) || [];
    
    // Add message to buffer
    threadBuffer.push(message);
    
    // Trim buffer if needed
    if (threadBuffer.length > this.bufferSize) {
      threadBuffer.splice(0, threadBuffer.length - this.bufferSize);
    }
    
    // Update buffer
    this.messageBuffer.set(threadId, threadBuffer);
  }
  
  /**
   * Remove inactive clients to prevent memory leaks
   */
  private cleanupInactiveClients(): void {
    const now = new Date();
    let removed = 0;
    
    this.clients.forEach((client, ws) => {
      // Check if inactive for more than 30 minutes
      const inactiveTime = now.getTime() - client.lastActivity.getTime();
      if (inactiveTime > 30 * 60 * 1000) {
        ws.terminate();
        this.clients.delete(ws);
        removed++;
      }
    });
    
    if (removed > 0) {
      console.log(`Cleaned up ${removed} inactive WebSocket connections`);
    }
  }
}
