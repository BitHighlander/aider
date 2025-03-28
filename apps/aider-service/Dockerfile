FROM node:18 AS base

# Install Python and Git
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv python3-full git build-essential curl

# Set working directory
WORKDIR /app

# Create a virtual environment
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

# Install Aider from the mounted directory
RUN mkdir -p /app/aider

# Copy package files for Node.js app
COPY package*.json ./
RUN npm ci

# Copy the rest of the application
COPY . .
RUN npm run build

# Expose port
EXPOSE 9876

# Set environment variables
ENV NODE_ENV=production
ENV PORT=9876

# Start the server with a shell script
COPY <<EOF /app/start.sh
#!/bin/bash
# Check if Aider directory is properly mounted
if [ -d "/app/aider" ] && [ "\$(ls -A /app/aider)" ]; then
  echo "Using mounted Aider directory"
  
  # Set a fake version for setuptools-scm
  export SETUPTOOLS_SCM_PRETEND_VERSION=0.0.0
  
  # Install Aider in development mode
  cd /app/aider
  pip install -e .
  
  # Start the server
  cd /app
  node dist/index.js
else
  echo "Aider directory not properly mounted"
  exit 1
fi
EOF

RUN chmod +x /app/start.sh

CMD ["/app/start.sh"]
