# Aider Service Deployment Guide (MAGA Protocol)

This document outlines the deployment process for the Aider Service following the Guild's MAGA (Master Always Green Approach) deployment protocol.

## Deployment Architecture

The Aider Service follows a multi-environment deployment architecture:

1. **Development** - For integration testing and early verification
2. **Staging** - For pre-production validation
3. **Production** - For end-user access

Each environment is progressively more restricted in terms of deployment access, with production requiring explicit approval.

## MAGA Workflow

![MAGA Workflow](https://i.imgur.com/KJntgqi.png)

### Key Principles

1. **M**ultiple environment validation before production
2. **A**utomated testing at each stage
3. **G**radual promotion through environments
4. **A**uditable and consistent processes

### Verification Scripts

The service includes two key verification scripts:

1. **verify-deployment-health.sh** - Verifies a specific deployment's health
2. **validate-maga-workflow.sh** - Validates the entire MAGA workflow

#### Usage Examples

```bash
# Check deployment health in development
./scripts/verify-deployment-health.sh -s aider-service -e development

# Validate MAGA workflow for a feature branch
./scripts/validate-maga-workflow.sh -b feature/new-feature -e development -s aider-service

# Test mode (skip actual checks)
./scripts/validate-maga-workflow.sh -t
```

## Deployment Process

### Local Development

1. Create feature branch from `develop`:
   ```bash
   git checkout develop
   git pull
   git checkout -b feature/my-feature
   ```

2. Implement and test locally:
   ```bash
   cd apps/aider-service
   npm install
   npm run test
   npm run build
   npm run start
   ```

3. Verify health locally:
   ```bash
   curl http://localhost:3100/api/health
   ```

### CI/CD Pipeline

Our CircleCI configuration automates the deployment process:

1. **Test**: Runs linting, unit tests, and builds the application
2. **Build**: Creates Docker image and pushes to registry
3. **Deploy**: Deploys to Kubernetes environment and verifies health
4. **Verify**: Runs MAGA verification to ensure deployment quality

### Deployment Environments

| Environment | URL | Purpose | Branch |
|-------------|-----|---------|--------|
| Development | https://dev.aider-service.pioneerdesktop.com | Feature testing | develop, feature/* |
| Staging | https://staging.aider-service.pioneerdesktop.com | Pre-production validation | develop |
| Production | https://aider-service.pioneerdesktop.com | End-user access | master |

## Monitoring

### Health Checks

The service exposes a MAGA-compliant `/api/health` endpoint that returns:

```json
{
  "status": "UP",
  "version": "1.0.0",
  "timestamp": "2025-03-26T18:00:00Z",
  "uptime": 3600,
  "components": {
    "aider": {
      "status": "UP",
      "details": { "version": "Aider service activated" }
    },
    "database": {
      "status": "UP"
    }
  },
  "metrics": {
    "memory": {
      "rss": "120MB",
      "heapTotal": "60MB",
      "heapUsed": "40MB"
    },
    "instances": {
      "running": 3,
      "total": 5
    }
  }
}
```

### Logging

All deployments use standardized logging:

1. Application logs are sent to stdout/stderr
2. Container logs are collected by Kubernetes
3. Logs are aggregated in our central logging system

## Rollback Procedures

If a deployment fails verification:

1. Automatic rollback: CircleCI will not promote to the next environment
2. Manual rollback:
   ```bash
   # Roll back to previous version
   kubectl -n pioneer rollout undo deployment/aider-service
   
   # Roll back to specific version
   kubectl -n pioneer rollout undo deployment/aider-service --to-revision=2
   ```

3. After rollback, run verification to ensure health:
   ```bash
   ./scripts/verify-deployment-health.sh -s aider-service -e production
   ```

## MAGA Compliance Requirements

All deployments must:

1. Pass all automated tests
2. Pass MAGA verification in all environments
3. Generate a MAGA status report
4. Have documented rollback procedures

## Security Protocols

1. OpenAI API keys are stored as Kubernetes secrets
2. MongoDB credentials are managed through environment variables
3. Container images are scanned for vulnerabilities

## Reference

- [Guild Deployment Protocol (MAGA-DEPLOY-001)](/docs/guild/DEPLOYMENT_PROTOCOL.md)
- [MAGA Status Verification Guide](/docs/deployment/rules/MAGA_STATUS_VERIFICATION.md)
- [CircleCI Setup](/docs/deployment/circleci-setup.md)
