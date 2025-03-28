import { Router, Request, Response } from 'express';
import { AiderService } from '../services/AiderService';
import { AiderState } from '../models/AiderState';

/**
 * Create API router for Aider service
 * @param aiderService The Aider service instance
 * @returns Express router
 */
export default function createRouter(aiderService: AiderService): Router {
  const router = Router();

  /**
   * Health check endpoint - MAGA-compliant
   */
  router.get('/health', (req: Request, res: Response) => {
    // Process metrics
    const uptime = process.uptime();
    const memoryUsage = process.memoryUsage();
    
    // Get instance counts to verify service functionality
    const runningInstances = Array.from(aiderService.getAllStatuses().values())
      .filter(status => status.state === AiderState.RUNNING).length;
    
    // Service status assessment
    let status = 'UP';
    const components: Record<string, {status: string, details?: any}> = {
      aider: { 
        status: 'UP',
        details: { version: 'Aider service activated' }
      },
      database: { 
        status: aiderService.isDatabaseConnected() ? 'UP' : 'DOWN' 
      }
    };
    
    // If database is down, service is degraded
    if (components.database.status === 'DOWN') {
      status = 'DEGRADED';
    }

    // MAGA-compliant health response
    res.json({
      status,
      version: '1.0.0',
      timestamp: new Date().toISOString(),
      uptime,
      components,
      metrics: {
        memory: {
          rss: Math.round(memoryUsage.rss / 1024 / 1024) + 'MB',
          heapTotal: Math.round(memoryUsage.heapTotal / 1024 / 1024) + 'MB',
          heapUsed: Math.round(memoryUsage.heapUsed / 1024 / 1024) + 'MB'
        },
        instances: {
          running: runningInstances,
          total: aiderService.getAllStatuses().size
        }
      }
    });
  });

  /**
   * Get all Aider instances
   */
  router.get('/instances', (req: Request, res: Response) => {
    const statuses = aiderService.getAllStatuses();
    const instances = Array.from(statuses.values());
    
    res.json({ instances });
  });

  /**
   * Start a new Aider instance
   */
  router.post('/instances', async (req: Request, res: Response) => {
    try {
      const config = req.body;
      const threadId = req.body.threadId || `aider-${Date.now()}`;
      
      const status = await aiderService.startAider(threadId, config);
      res.status(201).json(status);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      res.status(400).json({ error: errorMessage });
    }
  });

  /**
   * Get status of a specific Aider instance
   */
  router.get('/instances/:threadId', (req: Request, res: Response) => {
    const { threadId } = req.params;
    const status = aiderService.getStatus(threadId);
    
    if (!status) {
      return res.status(404).json({ error: `No Aider instance found with ID ${threadId}` });
    }
    
    res.json(status);
  });

  /**
   * Stop an Aider instance
   */
  router.delete('/instances/:threadId', async (req: Request, res: Response) => {
    try {
      const { threadId } = req.params;
      const status = await aiderService.stopAider(threadId);
      res.json(status);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      if (errorMessage.includes('No Aider instance found')) {
        return res.status(404).json({ error: errorMessage });
      }
      
      res.status(500).json({ error: errorMessage });
    }
  });

  /**
   * Send a command to an Aider instance
   */
  router.post('/instances/:threadId/command', async (req: Request, res: Response) => {
    try {
      const { threadId } = req.params;
      const { command } = req.body;
      
      if (!command) {
        return res.status(400).json({ error: 'Command required' });
      }

      const success = await aiderService.sendCommand(threadId, command);
      
      if (success) {
        res.json({ status: 'Command sent' });
      } else {
        res.status(404).json({ error: 'Process not found or cannot receive commands' });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      res.status(500).json({ error: `Command failed: ${errorMessage}` });
    }
  });

  return router;
}
