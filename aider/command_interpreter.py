#!/usr/bin/env python3
"""
Command Interpreter for Aider

This module provides a non-interactive, command-based interface to Aider,
designed for integration with REST APIs and other programmatic interfaces.
"""

import os
import sys
import json
import threading
import traceback
from io import StringIO
from typing import Dict, List, Optional, Any, Tuple, Union
from pathlib import Path
from contextlib import contextmanager

from aider.main import main as aider_main
from aider.coders import Coder
from aider.io import InputOutput
from aider.models import Model
from aider.commands import Commands, SwitchCoder
from aider.editors.base_editor import EditorError


class OutputCapture:
    """Captures stdout and stderr for processing by the command interpreter"""
    
    def __init__(self):
        self.buffer = StringIO()
        self.messages = []
        self.error_messages = []
        self.warning_messages = []
        self.current_type = "output"  # output, error, warning
        
    def write(self, text):
        self.buffer.write(text)
        
        # Categorize the message based on content
        if text.strip():
            if text.strip().startswith("ERROR:"):
                self.error_messages.append(text)
                self.current_type = "error"
            elif text.strip().startswith("WARNING:"):
                self.warning_messages.append(text)
                self.current_type = "warning"
            else:
                self.messages.append(text)
                self.current_type = "output"
        
        return len(text)
    
    def flush(self):
        self.buffer.flush()
    
    def get_output(self) -> str:
        """Get all captured output as a string"""
        return self.buffer.getvalue()
    
    def get_structured_output(self) -> Dict[str, List[str]]:
        """Get categorized output"""
        return {
            "output": self.messages,
            "errors": self.error_messages,
            "warnings": self.warning_messages,
        }


class InputFeeder:
    """Feeds input to Aider based on commands"""
    
    def __init__(self):
        self.command_queue = []
        self.current_index = 0
        self.last_command = None
        self._lock = threading.Lock()
    
    def queue_input(self, command):
        """Add a command to the queue"""
        with self._lock:
            self.command_queue.append(command)
            self.last_command = command
    
    def clear_queue(self):
        """Clear the command queue"""
        with self._lock:
            self.command_queue = []
            self.current_index = 0
    
    def readline(self):
        """Read a line from the queue - used by Aider's input handling"""
        with self._lock:
            if self.current_index < len(self.command_queue):
                command = self.command_queue[self.current_index]
                self.current_index += 1
                return command + "\n"
            return "exit\n"  # Exit command when queue is empty


class CommandResponse:
    """Structured response from command execution"""
    
    def __init__(
        self, 
        command: str, 
        success: bool = True, 
        output: str = "", 
        error: Optional[str] = None,
        files_changed: Optional[List[str]] = None
    ):
        self.command = command
        self.success = success
        self.output = output
        self.error = error
        self.files_changed = files_changed or []
        self.warnings = []
        self.timestamp = None  # Will be set when serialized
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for JSON serialization"""
        import datetime
        
        return {
            "command": self.command,
            "success": self.success,
            "output": self.output,
            "error": self.error,
            "files_changed": self.files_changed,
            "warnings": self.warnings,
            "timestamp": datetime.datetime.now().isoformat(),
        }
    
    def to_json(self) -> str:
        """Convert to JSON string"""
        return json.dumps(self.to_dict())


class CommandInterpreter:
    """
    Main class for converting between command-based and interactive Aider interfaces
    
    This class initializes Aider in a special mode that captures all I/O and
    redirects it through controlled channels, allowing for programmatic interaction.
    """
    
    def __init__(
        self, 
        repo_path: str,
        model: str = "gpt-4",
        api_key: Optional[str] = None,
        verbose: bool = False,
        auto_commit: bool = False,
    ):
        self.repo_path = os.path.abspath(repo_path)
        self.model = model
        self.verbose = verbose
        self.auto_commit = auto_commit
        
        # Set API key if provided
        if api_key:
            os.environ["OPENAI_API_KEY"] = api_key
        
        # Initialize state
        self.coder = None
        self.output_capture = OutputCapture()
        self.input_feeder = InputFeeder()
        self.modified_files = set()
        self.last_error = None
        
        # Initialize Aider
        self._initialize()
        
    @contextmanager
    def _redirect_io(self):
        """Context manager to redirect stdin/stdout/stderr"""
        old_stdin = sys.stdin
        old_stdout = sys.stdout
        old_stderr = sys.stderr
        
        # Redirect
        sys.stdin = self.input_feeder
        sys.stdout = self.output_capture
        sys.stderr = self.output_capture
        
        try:
            yield
        finally:
            # Restore
            sys.stdin = old_stdin
            sys.stdout = old_stdout
            sys.stderr = old_stderr
    
    def _initialize(self):
        """Initialize Aider with non-interactive settings"""
        try:
            with self._redirect_io():
                # Setup args for initialization
                argv = [
                    "--yes-always",  # Auto-answer yes to prompts
                    "--model", self.model,
                    "--no-git-verify",  # Skip git pre-commit hooks
                ]
                
                if self.auto_commit:
                    argv.append("--auto-commits")
                
                # Add repo path - this is critical to have as the correct path
                repo_path = os.path.abspath(self.repo_path)
                argv.append(repo_path)
                
                if self.verbose:
                    print(f"CommandInterpreter: initializing with repo path: {repo_path}")
                
                # Initialize Aider and get coder instance
                self.coder = aider_main(
                    argv=argv,
                    input=self.input_feeder,
                    output=self.output_capture,
                    force_git_root=repo_path,  # Force the git root to be the repo path
                    return_coder=True
                )
                
                if not self.coder:
                    raise RuntimeError("Failed to initialize Aider")
                
                # Ensure the repo is the working directory for file operations
                os.chdir(repo_path)
                if self.verbose:
                    print(f"CommandInterpreter: changed working directory to {repo_path}")
                
                # Store the commands interface for accessing methods directly
                self.commands = self.coder.commands
                
                if self.verbose:
                    print(f"CommandInterpreter: initialized for repository: {self.repo_path}")
                    
        except Exception as e:
            self.last_error = str(e)
            traceback.print_exc()
            raise RuntimeError(f"Failed to initialize Aider: {e}")
    
    def execute_command(self, command: str) -> CommandResponse:
        """Execute a single command and return the results"""
        if not self.coder:
            return CommandResponse(
                command=command,
                success=False,
                error="Aider not initialized properly"
            )
        
        # Create response object
        response = CommandResponse(command=command)
        
        # Capture the current list of files for comparison later
        current_files = set()
        try:
            if hasattr(self.coder, 'get_all_relative_files'):
                current_files = set(self.coder.get_all_relative_files())
        except Exception:
            pass
        
        # Clear previous output
        self.output_capture = OutputCapture()
        self.input_feeder.clear_queue()
        self.input_feeder.queue_input(command)
        
        try:
            with self._redirect_io():
                # Handle commands with / prefix
                if command.startswith("/"):
                    cmd_name = command[1:].split()[0]
                    args = command[1 + len(cmd_name):].strip()
                    
                    # Find the command method
                    cmd_method = getattr(self.commands, f"cmd_{cmd_name}", None)
                    if cmd_method:
                        cmd_method(args)
                    else:
                        raise ValueError(f"Unknown command: {cmd_name}")
                else:
                    # Send query to Aider LLM
                    self.coder.run_chat_loop(
                        with_message=command,
                        quiet=True,
                    )
                
                # Get the captured output
                response.output = self.output_capture.get_output()
                
                # Compare files to detect changes
                try:
                    if hasattr(self.coder, 'get_all_relative_files'):
                        new_files = set(self.coder.get_all_relative_files())
                        response.files_changed = list(new_files - current_files)
                        # Also add modified files if we can detect them
                        if hasattr(self.coder, 'get_modified_files'):
                            modified = self.coder.get_modified_files()
                            response.files_changed.extend([f for f in modified if f not in response.files_changed])
                except Exception as e:
                    response.warnings.append(f"Error detecting file changes: {e}")
                
        except SwitchCoder:
            # Handle coder switching (e.g., when changing models)
            response.output = self.output_capture.get_output()
            response.warnings.append("Coder was switched during command execution")
        except Exception as e:
            response.success = False
            response.error = str(e)
            response.output = self.output_capture.get_output()
            if self.verbose:
                traceback.print_exc()
        
        return response
    
    def get_repository_files(self) -> List[str]:
        """Get a list of files in the repository that Aider can work with"""
        if not self.coder:
            return []
            
        files = []
        try:
            files = list(self.coder.get_all_relative_files())
        except Exception as e:
            if self.verbose:
                print(f"Error getting repository files: {e}")
                
        return files
    
    def get_status(self) -> Dict[str, Any]:
        """Get current status information about the Aider instance"""
        status = {
            "initialized": self.coder is not None,
            "repository": self.repo_path,
            "model": self.model,
            "auto_commit": self.auto_commit,
            "last_error": self.last_error,
        }
        
        # Add more details if available
        if self.coder:
            try:
                # Add git status if available
                if hasattr(self.coder, 'repo') and self.coder.repo:
                    status["git_initialized"] = True
                    status["git_tracked_files"] = len(self.coder.repo.get_tracked_files())
                else:
                    status["git_initialized"] = False
                
                # Add edit format
                if hasattr(self.coder, 'edit_format'):
                    status["edit_format"] = self.coder.edit_format
            except Exception as e:
                status["status_error"] = str(e)
        
        return status
    
    def shutdown(self):
        """Clean up resources when shutting down"""
        # Nothing specific to clean up at the moment
        self.coder = None
        if self.verbose:
            print("CommandInterpreter: shutdown complete")


# Command-line interface for testing
if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="Aider Command Interpreter")
    parser.add_argument("repo_path", help="Path to the git repository")
    parser.add_argument("--model", default="gpt-4", help="Model to use")
    parser.add_argument("--command", help="Command to execute")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    parser.add_argument("--auto-commit", action="store_true", help="Enable auto-commits")
    
    args = parser.parse_args()
    
    interpreter = CommandInterpreter(
        repo_path=args.repo_path,
        model=args.model,
        verbose=args.verbose,
        auto_commit=args.auto_commit
    )
    
    if args.command:
        response = interpreter.execute_command(args.command)
        print(json.dumps(response.to_dict(), indent=2))
    else:
        # Interactive command mode for testing
        print(f"Aider Command Interpreter initialized for {args.repo_path}")
        print("Type commands (or 'exit' to quit):")
        
        while True:
            try:
                command = input("> ")
                if command.lower() in ["exit", "quit"]:
                    break
                    
                response = interpreter.execute_command(command)
                print("\nOutput:")
                print(response.output)
                
                if response.error:
                    print(f"\nError: {response.error}")
                
                if response.files_changed:
                    print(f"\nFiles changed: {', '.join(response.files_changed)}")
            except KeyboardInterrupt:
                break
            except Exception as e:
                print(f"Error: {e}")
                traceback.print_exc()
