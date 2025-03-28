import { ChildProcess, spawn } from 'child_process';
import path from 'path';
import fs from 'fs';
import { AiderState, AiderStatus } from '../models/AiderState';
import { LoggingService } from './LoggingService';
import { MongoClient } from 'mongodb';

/**
 * Configuration for Aider instances
 */
export interface AiderConfiguration {
  openAIApiKey: string;
  githubToken?: string;
  model?: string;
  projectRoot: string;
  allowedFileTypes?: string[];
  autoCommit?: boolean;
}

/**
 * Instance state for database storage
 */
interface AiderInstanceState {
  threadId: string;
  status: AiderStatus;
  lastActivity: Date;
  configuration: AiderConfiguration;
}

/**
 * Service to manage Aider AI assistant instances
 */
export class AiderService {
  private instances: Map<string, {
    process: ChildProcess | null;
    status: AiderStatus;
    configuration: AiderConfiguration;
    lastActivity: Date;
  }> = new Map();
  
  private aiderRoot: string;
  private loggingService: LoggingService;
  private static readonly STATE_COLLECTION = 'aider_states';
  private mongoUri?: string;
  private mongoClient: MongoClient | null = null;
  private dbConnected: boolean = false;

  /**
   * Create a new AiderService
   * @param loggingService Service for logging and broadcasting messages
   * @param mongoUri Optional MongoDB connection URI for state persistence
   */
  constructor(loggingService: LoggingService, mongoUri?: string) {
    // Check possible locations for Aider
    const possiblePaths = [
      '/app/aider', // Docker mounted path
      path.resolve(__dirname, '../../../..', 'aider'), // Local dev path
      path.resolve(__dirname, '../../..', 'aider'), // Alternative path
      '/aider' // Another possible Docker path
    ];
    
    // Find the first valid path
    this.aiderRoot = possiblePaths.find(p => fs.existsSync(p)) || '';
    
    this.loggingService = loggingService;
    this.mongoUri = mongoUri;
    
    // Validate Aider installation
    if (!this.aiderRoot) {
      console.error('Tried these paths for Aider:', possiblePaths);
      throw new Error(`Aider not found. Run 'git submodule update --init --recursive'`);
    }
    
    console.log(`Using Aider installation at: ${this.aiderRoot}`);

    // Initialize database connection if URI provided
    if (mongoUri) {
      this.initDbConnection(mongoUri).catch(err => {
        console.error('Failed to initialize database connection:', err);
      });
    }
  }

  /**
   * Start Aider instance for a given thread
   * @param threadId Unique identifier for this Aider instance
   * @param config Configuration for this Aider instance
   * @returns Status of the started instance
   */
  public async startAider(threadId: string, config: AiderConfiguration): Promise<AiderStatus> {
    // Validate configuration
    this.validateConfig(config);

    // Check if instance already exists
    if (this.instances.has(threadId)) {
      const existing = this.instances.get(threadId)!;
      if (existing.process && existing.status.state === AiderState.RUNNING) {
        throw new Error(`Aider instance with ID ${threadId} is already running`);
      }
    }

    try {
      // Build command-line arguments for command interpreter
      const args = [
        '-m', 'aider.command_interpreter',  // Use our command interpreter
        config.projectRoot,  // Pass project root as positional argument
        '--model', config.model || 'gpt-4',
        '--verbose'
      ];
      
      if (config.autoCommit) {
        args.push('--auto-commit');
      }
      
      // Execute Aider with command interpreter
      const aiderProcess = spawn('python3', args, {
        cwd: this.aiderRoot,  // Run from aider directory where the module is
        env: {
          ...process.env,
          OPENAI_API_KEY: config.openAIApiKey,
          GITHUB_TOKEN: config.githubToken || '',
          AIDER_PROJECT_ROOT: config.projectRoot // Also pass as environment variable
        },
        stdio: ['pipe', 'pipe', 'pipe']
      });
      
      // Create initial status
      const status: AiderStatus = {
        state: AiderState.RUNNING,
        diagnosticMessage: 'Aider started successfully',
        threadId,
        configuration: config
      };
      
      // Store the running instance
      this.instances.set(threadId, {
        process: aiderProcess,
        status,
        configuration: config,
        lastActivity: new Date()
      });
      
      // Set up output parsers for JSON responses
      let buffer = '';
      
      aiderProcess.stdout.on('data', (data) => {
        const text = data.toString();
        buffer += text;
        
        // Check if we have complete JSON in the buffer
        if (this.isCompleteJson(buffer)) {
          try {
            const response = JSON.parse(buffer);
            // Process structured response
            this.handleStructuredResponse(threadId, response);
            // Clear buffer after successful parsing
            buffer = '';
          } catch (error) {
            // Not a JSON response or malformed JSON
            // Log the raw output and continue accumulating
            this.loggingService.broadcastLog(threadId, text);
          }
        } else if (text.includes('\n')) {
          // If we have newlines but not complete JSON, it's probably regular output
          this.loggingService.broadcastLog(threadId, text);
          buffer = ''; // Clear non-JSON buffer
        }
      });
      
      aiderProcess.stderr.on('data', (data) => {
        this.loggingService.broadcastLog(threadId, `ERROR: ${data.toString()}`, 'error');
      });
      
      // Handle process exit
      aiderProcess.on('exit', (code) => {
        const instance = this.instances.get(threadId);
        if (instance) {
          instance.status.state = code === 0 ? AiderState.COMPLETED : AiderState.HALTED;
          instance.status.diagnosticMessage = code === 0 
            ? 'Completed successfully' 
            : `Process exited with code ${code}`;
          instance.process = null;
          
          this.loggingService.broadcastLog(threadId, `Aider process exited with code ${code}`);
          this.persistState(threadId);
        }
      });
      
      // Wait a moment for initialization
      await new Promise(resolve => setTimeout(resolve, 2000));
      
      // Persist the initial state
      await this.persistState(threadId);
      
      return status;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      const status: AiderStatus = {
        state: AiderState.HALTED,
        diagnosticMessage: `Failed to start Aider: ${errorMessage}`,
        threadId,
        configuration: config
      };
      
      // Still record the failed attempt
      this.instances.set(threadId, {
        process: null,
        status,
        configuration: config,
        lastActivity: new Date()
      });
      
      await this.persistState(threadId);
      throw error;
    }
  }
  
  /**
   * Check if a string contains a complete JSON object
   * @param str String to check
   * @private
   */
  private isCompleteJson(str: string): boolean {
    try {
      // Try to parse the string as JSON
      JSON.parse(str);
      // If parsing succeeds and the string starts with '{' and ends with '}', it's complete JSON
      return str.trim().startsWith('{') && str.trim().endsWith('}');
    } catch (e) {
      // If parsing fails, it's not complete JSON
      return false;
    }
  }

  /**
   * Handle a structured response from the command interpreter
   * @param threadId Thread ID that produced the response
   * @param response Structured response object
   * @private
   */
  private handleStructuredResponse(threadId: string, response: any): void {
    // Log the main output
    if (response.output) {
      this.loggingService.broadcastLog(threadId, response.output);
    }
    
    // Log any errors
    if (response.error) {
      this.loggingService.broadcastLog(threadId, `ERROR: ${response.error}`, 'error');
    }
    
    // Log any warnings
    if (response.warnings && response.warnings.length > 0) {
      for (const warning of response.warnings) {
        this.loggingService.broadcastLog(threadId, `WARNING: ${warning}`, 'info');
      }
    }
    
    // Log file changes
    if (response.files_changed && response.files_changed.length > 0) {
      this.loggingService.broadcastLog(
        threadId, 
        `Files changed: ${response.files_changed.join(', ')}`,
        'info'
      );
    }
  }

  /**
   * Stop a running Aider instance
   * @param threadId The thread ID to stop
   * @returns Updated status of the stopped instance
   */
  public async stopAider(threadId: string): Promise<AiderStatus> {
    const instance = this.instances.get(threadId);
    
    if (!instance) {
      throw new Error(`No Aider instance found with ID ${threadId}`);
    }
    
    try {
      // If process is running, kill it
      if (instance.process) {
        instance.process.kill();
        
        // Update status
        instance.status.state = AiderState.HALTED;
        instance.status.diagnosticMessage = 'Stopped by user request';
        instance.process = null;
        
        this.loggingService.broadcastLog(threadId, `Aider process exited with code ${0}`);
        this.persistState(threadId);
      }
      
      await this.persistState(threadId);
      return instance.status;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      this.loggingService.broadcastLog(threadId, `Error stopping Aider: ${errorMessage}`);
      throw error;
    }
  }
  
  /**
   * Get the current status of an Aider instance
   * @param threadId Thread ID to check
   * @returns Current status of the specified instance
   */
  public getStatus(threadId: string): AiderStatus | null {
    const instance = this.instances.get(threadId);
    if (!instance) return null;
    return instance.status;
  }
  
  /**
   * Get the status of all Aider instances
   * @returns Map of thread IDs to their statuses
   */
  public getAllStatuses(): Map<string, AiderStatus> {
    const statuses = new Map<string, AiderStatus>();
    this.instances.forEach((instance, threadId) => {
      statuses.set(threadId, instance.status);
    });
    return statuses;
  }
  
  /**
   * Send a command to a running Aider instance
   * @param threadId The thread ID to send the command to
   * @param command The command text to send
   * @returns Whether the command was sent successfully
   */
  public async sendCommand(threadId: string, command: string): Promise<boolean> {
    const instance = this.instances.get(threadId);
    if (!instance?.process?.stdin) return false;
    
    return new Promise<boolean>((resolve) => {
      // Format command for our command interface
      // If it's a / command, send it directly, otherwise format as JSON
      const formattedCommand = command.startsWith('/') 
        ? command + '\n' 
        : JSON.stringify({ command }) + '\n';

      instance.process!.stdin!.write(formattedCommand, (err) => {
        if (err) {
          this.loggingService.broadcastLog(threadId, `Error sending command: ${err.message}`, 'error');
          resolve(false);
        } else {
          // Update last activity time
          instance.lastActivity = new Date();
          this.persistState(threadId);
          
          // Log the command
          this.loggingService.broadcastLog(threadId, `Command sent: ${command}`);
          resolve(true);
        }
      });
    });
  }
  
  /**
   * Load previously saved states from the database
   */
  public async restoreStates(): Promise<void> {
    if (!this.mongoUri) return;
    
    try {
      const client = new MongoClient(this.mongoUri);
      await client.connect();
      
      const states = await client.db()
        .collection<AiderInstanceState>(AiderService.STATE_COLLECTION)
        .find({})
        .toArray();
      
      for (const state of states) {
        // Restore state but mark as not running
        if (state.status.state === AiderState.RUNNING) {
          state.status.state = AiderState.HALTED;
          state.status.diagnosticMessage = 'Process terminated during service restart';
        }
        
        this.instances.set(state.threadId, {
          process: null,
          status: state.status,
          configuration: state.configuration,
          lastActivity: state.lastActivity
        });
      }
      
      await client.close();
      console.log(`Restored ${states.length} Aider instances from database`);
    } catch (error) {
      console.error('Failed to restore Aider states:', error);
    }
  }
  
  /**
   * Validate Aider configuration
   * @param config Configuration to validate
   */
  private validateConfig(config: AiderConfiguration): void {
    if (!config.openAIApiKey) {
      throw new Error('OpenAI API key is required');
    }
    
    if (!config.projectRoot) {
      throw new Error('Project root directory is required');
    }
    
    // Ensure directory exists
    if (!fs.existsSync(config.projectRoot)) {
      throw new Error(`Project directory not found: ${config.projectRoot}`);
    }
  }
  
  /**
   * Persist an instance state to the database
   * @param threadId Thread ID to persist
   */
  private async persistState(threadId: string): Promise<void> {
    if (!this.mongoUri) return;
    
    const instance = this.instances.get(threadId);
    if (!instance) return;
    
    try {
      const client = new MongoClient(this.mongoUri);
      await client.connect();
      
      await client.db()
        .collection<AiderInstanceState>(AiderService.STATE_COLLECTION)
        .updateOne(
          { threadId },
          { 
            $set: {
              threadId,
              status: instance.status,
              configuration: instance.configuration,
              lastActivity: instance.lastActivity
            } 
          },
          { upsert: true }
        );
      
      await client.close();
    } catch (error) {
      console.error(`Failed to persist state for thread ${threadId}:`, error);
    }
  }

  /**
   * Check if the database is connected
   * @returns Whether the database is connected
   */
  public isDatabaseConnected(): boolean {
    return this.dbConnected;
  }

  /**
   * Initialize database connection
   * @param uri MongoDB connection URI
   */
  private async initDbConnection(uri: string): Promise<void> {
    try {
      this.mongoClient = new MongoClient(uri);
      await this.mongoClient.connect();
      // Test connection with a simple command
      await this.mongoClient.db().command({ ping: 1 });
      this.dbConnected = true;
      console.log('MongoDB connection established successfully');
    } catch (error) {
      this.dbConnected = false;
      console.error('MongoDB connection failed:', error);
    }
  }
}
