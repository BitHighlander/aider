#!/usr/bin/env python3
"""
Command Interface for Aider - Enables non-interactive command-based operation

This module extends Aider to support REST API integration by allowing
commands to be executed without requiring an interactive terminal session.
"""

import os
import sys
import json
import argparse
import threading
from pathlib import Path
from io import StringIO
from typing import Dict, List, Optional, Tuple, Union

from aider.main import main as aider_main
from aider.coders import Coder
from aider.io import InputOutput
from aider.commands import Commands
from aider.models import Model


class CommandOutputCapture:
    """Capture output from Aider's IO to return it to the caller"""
    
    def __init__(self):
        self.output_buffer = StringIO()
        self.captured_content = []
        
    def write(self, content):
        self.output_buffer.write(content)
        self.captured_content.append(content)
        
    def flush(self):
        self.output_buffer.flush()
        
    def getvalue(self):
        return self.output_buffer.getvalue()
    
    def get_captured_content(self):
        return "".join(self.captured_content)


class CommandInputFeeder:
    """Feed commands to Aider's IO as if they came from a user"""
    
    def __init__(self, commands=None):
        self.commands = commands or []
        self.command_index = 0
        
    def readline(self):
        if self.command_index < len(self.commands):
            command = self.commands[self.command_index]
            self.command_index += 1
            return command + "\n"
        return "exit\n"  # Exit after all commands are processed


class AiderCommandInterface:
    """Interface for running Aider in command mode rather than interactive mode"""
    
    def __init__(
        self, 
        repo_path: str, 
        model: str = "gpt-4", 
        api_key: Optional[str] = None,
        verbose: bool = False
    ):
        self.repo_path = os.path.abspath(repo_path)
        self.model = model
        self.verbose = verbose
        self.coder = None
        self.commands = None
        
        # Set API key if provided
        if api_key:
            os.environ["OPENAI_API_KEY"] = api_key
        
        # Initialize Aider instance
        self._initialize()
        
    def _initialize(self):
        """Initialize Aider with proper settings for command-based operation"""
        # Save original stdin/stdout
        original_stdin = sys.stdin
        original_stdout = sys.stdout
        original_stderr = sys.stderr
        
        # Create capture for output
        output_capture = CommandOutputCapture()
        sys.stdout = output_capture
        sys.stderr = output_capture
        
        try:
            # Setup args for initialization
            argv = [
                "--yes-always",  # Auto-answer yes to prompts
                "--model", self.model,
                "--no-git-verify",  # Skip git pre-commit hooks
                self.repo_path
            ]
            
            # Initialize Aider and get coder instance
            self.coder = aider_main(
                argv=argv,
                return_coder=True,
                force_git_root=self.repo_path
            )
            
            if self.coder:
                # Store the commands interface for later use
                self.commands = self.coder.commands
                
                if self.verbose:
                    print(f"Aider initialized for repository: {self.repo_path}")
            else:
                print("Failed to initialize Aider")
        finally:
            # Restore stdin/stdout
            sys.stdin = original_stdin
            sys.stdout = original_stdout
            sys.stderr = original_stderr
            
            if self.verbose:
                print(output_capture.getvalue())
    
    def execute_command(self, command: str) -> Dict:
        """Execute a single command and return the results"""
        if not self.coder or not self.commands:
            return {"error": "Aider not initialized properly"}
        
        # Save original stdin/stdout
        original_stdin = sys.stdin
        original_stdout = sys.stdout
        original_stderr = sys.stderr
        
        # Create input and output handlers
        input_feeder = CommandInputFeeder([command])
        output_capture = CommandOutputCapture()
        
        # Redirect IO
        sys.stdin = input_feeder
        sys.stdout = output_capture
        sys.stderr = output_capture
        
        result = {
            "command": command,
            "output": "",
            "success": False,
            "error": None
        }
        
        try:
            # Handle commands with / prefix
            if command.startswith("/"):
                cmd_name = command[1:].split()[0]
                args = command[1 + len(cmd_name):].strip()
                
                # Find the command method
                cmd_method = getattr(self.commands, f"cmd_{cmd_name}", None)
                if cmd_method:
                    cmd_method(args)
                    result["success"] = True
                else:
                    result["error"] = f"Unknown command: {cmd_name}"
            else:
                # Send query to Aider LLM
                self.coder.run_chat_loop(
                    with_message=command,
                    quiet=True,
                )
                result["success"] = True
        except Exception as e:
            result["error"] = str(e)
        finally:
            # Restore stdin/stdout
            sys.stdin = original_stdin
            sys.stdout = original_stdout
            sys.stderr = original_stderr
            
            # Get the captured output
            result["output"] = output_capture.get_captured_content()
            
        return result

    def get_repository_files(self) -> List[str]:
        """Get a list of files in the repository that Aider can work with"""
        if not self.coder:
            return []
            
        files = []
        try:
            for fname in self.coder.get_all_relative_files():
                files.append(fname)
        except Exception as e:
            if self.verbose:
                print(f"Error getting repository files: {e}")
                
        return files


# Command-line interface for testing
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Aider Command Interface")
    parser.add_argument("repo_path", help="Path to the git repository")
    parser.add_argument("--model", default="gpt-4", help="Model to use")
    parser.add_argument("--command", help="Command to execute")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    
    args = parser.parse_args()
    
    interface = AiderCommandInterface(
        repo_path=args.repo_path,
        model=args.model,
        verbose=args.verbose
    )
    
    if args.command:
        result = interface.execute_command(args.command)
        print(json.dumps(result, indent=2))
    else:
        # Interactive command mode for testing
        print(f"Aider Command Interface initialized for {args.repo_path}")
        print("Type commands (or 'exit' to quit):")
        
        while True:
            try:
                command = input("> ")
                if command.lower() in ["exit", "quit"]:
                    break
                    
                result = interface.execute_command(command)
                print("Output:")
                print(result["output"])
                
                if result["error"]:
                    print(f"Error: {result['error']}")
            except KeyboardInterrupt:
                break
