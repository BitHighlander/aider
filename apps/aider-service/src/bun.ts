#!/usr/bin/env bun
/**
 * Bun startup script for Aider REST service
 * This script provides optimized startup for Bun runtime
 */

import { spawn } from 'child_process';
import { resolve } from 'path';

console.log('🚀 Starting Aider Service with Bun runtime');

// Environment check
if (!process.env.OPENAI_API_KEY) {
  console.warn('⚠️  Warning: OPENAI_API_KEY environment variable not set');
  console.warn('   Aider instances will require this key to be provided in API requests');
}

// Check for Aider submodule
const aiderPath = resolve(__dirname, '../../..', 'aider');
try {
  const result = spawn('python3', ['-m', 'aider.main', '--version'], {
    cwd: aiderPath,
    stdio: 'pipe'
  });
  
  let output = '';
  result.stdout.on('data', (data) => {
    output += data.toString();
  });
  
  result.on('close', (code) => {
    if (code === 0) {
      console.log(`✅ Aider is properly installed: ${output.trim()}`);
    } else {
      console.error('❌ Aider installation check failed');
      console.error('   Run "git submodule update --init --recursive" to set up Aider');
    }
  });
} catch (error) {
  console.error('❌ Could not verify Aider installation:', error);
}

// Import and start the server
import './index';
