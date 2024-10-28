# SageMaker Notebook Setup

This repository contains scripts to set up an Amazon SageMaker notebook
instance with autostop functionality and code-server integration.

## Features

1. **Autostop**: Automatically stops idle instances outside active hours
2. **Code-Server**: Run VSCode in browser with HTTPS security
3. **Security**: HTTPS enabled, password protected, IP whitelisting

## Repository Structure

```bash
.
├── autostop/              # Autostop functionality
├── code-server/          # VSCode server setup
├── config/              # Configuration files
├── terraform/          # Infrastructure as Code
└── scripts/           # Utility scripts
```

## Prerequisites

- AWS account with SageMaker permissions
- IAM role with required access
- Basic AWS knowledge

## Quick Start

1. Clone repository
2. Configure settings
3. Deploy with Terraform
4. Access via browser

## Configuration

Edit `config/defaults.env` for:

- Idle timeout
- Active hours
- Security settings

## Security

- HTTPS enabled
- Password protected
- IP whitelisting
- Regular updates

## Support

Open an issue for help.

## License

MIT
