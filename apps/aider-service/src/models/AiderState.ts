/**
 * Enum representing the possible states of an Aider instance
 */
export enum AiderState {
  NOT_CONFIGURED = "NOT_CONFIGURED",
  RUNNING = "RUNNING",
  HALTED = "HALTED",
  COMPLETED = "COMPLETED"
}

/**
 * Interface for Aider status information
 */
export interface AiderStatus {
  state: AiderState;
  diagnosticMessage?: string;
  projectPath?: string;
  threadId: string;
  configuration: AiderConfiguration;
  startTime?: Date;
  endTime?: Date;
}

/**
 * Interface for Aider configuration
 */
export interface AiderConfig {
  openAiApiKey: string;
  workingDirectory: string;
  modelName?: string;
  githubToken?: string;
  additionalArgs?: string[];
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Interface representing a project/thread for Aider
 */
export interface AiderProject {
  id: string;
  name: string;
  path: string;
  status: AiderStatus;
  config: AiderConfig;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * Interface for Aider configuration
 */
export interface AiderConfiguration {
  openAIApiKey: string;
  githubToken?: string;
  model?: string;
  projectRoot: string;
  allowedFileTypes?: string[];
}
