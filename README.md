# SageMaker VS Code Integration

Automate the deployment of AWS SageMaker notebook instances with integrated VS Code support through code-server.

## Features

- 🚀 One-click SageMaker notebook instance deployment
- 💻 Integrated VS Code environment via code-server
- 🔒 Secure VPC configuration with customizable security groups
- ⚡ Automatic VS Code extension installation
- 💤 Idle instance management to control costs
- 🔄 Persistent VS Code settings across sessions

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0.0
- Bash shell environment
- IAM role with SageMaker permissions
- VPC and subnet with appropriate network access

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd <repository-name>
   ```

2. Configure your environment:
   ```bash
   cp config/defaults.env.example config/defaults.env
   # Edit defaults.env with your preferred settings
   ```

3. Run the setup script:
   ```bash
   ./setup_sagemaker.sh
   ```

## Configuration

### Environment Variables

Key settings in `config/defaults.env`:

- `AWS_PROFILE`: AWS CLI profile to use
- `AWS_REGION`: Target AWS region
- `INSTANCE_TYPE`: SageMaker instance type (e.g., ml.t3.large)
- `TIMEZONE`: Instance timezone
- `IDLE_TIME`: Auto-shutdown timeout in seconds

### Security Groups

The deployment creates a security group with:
- HTTPS (443) access
- HTTP (80) access
- Neo4j ports (7474, 7473, 7687)
- Configurable CIDR blocks for access control

## VS Code Integration

### Extensions

Place a `.vscode/extensions.json` file in your project:
```json
{
  "recommendations": [
    "ms-python.python",
    "ms-toolsai.jupyter"
  ]
}
```

Extensions will be automatically installed on instance start.

## Lifecycle Scripts

- `on_create.sh`: Initial instance setup and code-server installation
- `on_start.sh`: Starts code-server and manages VS Code extensions

## Cost Management

The instance includes automatic shutdown when idle for the configured duration (default: 1.5 hours).

## Security

- VPC isolation enabled by default
- Security group with minimal required ports
- Pre-commit hooks for security scanning
- Infrastructure as Code security checks via checkov

## Contributing

Ensure all pre-commit hooks pass before submitting:
```bash
pre-commit install
pre-commit run --all-files
```
