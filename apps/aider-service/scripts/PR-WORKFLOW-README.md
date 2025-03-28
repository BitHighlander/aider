# JavaScript Typo Fixing PR Workflow with Aider

This directory contains scripts for demonstrating a complete PR workflow that uses Aider to automatically fix JavaScript typos and create a pull request.

## Workflow

The workflow consists of these steps:

1. Create a test repository with deliberate JavaScript typos
2. Have Aider fix the typos
3. Create a fork of the repository
4. Push the fixes to the fork
5. Create a pull request from the fork to the original repository

## Prerequisites

- GitHub personal access token with repo permissions (export as `GITHUB_TOKEN`)
- OpenAI API key (export as `OPENAI_API_KEY`)
- Aider Service running locally on port 3100

## Setup

1. Set the required environment variables:

```bash
export GITHUB_TOKEN=your_github_token
export OPENAI_API_KEY=your_openai_api_key
export GITHUB_USERNAME=your_github_username  # Optional, will be fetched if not provided
```

2. Start the Aider service:

```bash
cd apps/aider-service
npm run dev
```

## Usage

### 1. Create a Test Repository

First, create a test repository containing JavaScript files with deliberate typos:

```bash
./create-test-repo.sh
```

This will:
- Create a local git repository with JavaScript files containing typos
- Create a GitHub repository under your account
- Push the files to the repository
- Output the repository path for use in the next step

### 2. Run the PR Workflow

Run the PR workflow script with the repository path from the previous step:

```bash
./e2e-pr-workflow.sh
```

The script will prompt you to enter your GitHub username and the source repository if they're not provided.

## Script Details

### `create-test-repo.sh`

Creates a test repository with JavaScript files containing deliberate typos:

- `utils.js` - Utility functions with various typos
- `app.js` - Main application file with import errors
- `math.js` - Mathematical functions with syntax errors

### `e2e-pr-workflow.sh`

Runs the complete PR workflow:

1. Check if the Aider service is running
2. Clone the test repository
3. Start an Aider instance for the repository
4. Send a command to fix all JavaScript typos
5. Verify the changes made by Aider
6. Create a fork of the repository
7. Push the changes to the fork
8. Create a pull request to the original repository

## Troubleshooting

If the workflow fails, check the following:

1. Make sure the Aider service is running on port 3100
2. Verify your GitHub token has sufficient permissions
3. Check that your GitHub username is correctly set or detected
4. If the fork already exists, the script will use it instead of creating a new one
5. If the PR creation fails, it might be because there's already an open PR for the same branch

## Example Output

After successful completion, you should see:

```
Pull request created successfully
PR URL: https://github.com/your-username/js-typo-test/pull/1
```

You can then visit the PR URL to review the changes made by Aider. 