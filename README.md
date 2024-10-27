# SageMaker Notebook Setup: Autostop and Code-Server

This repository contains scripts to set up an Amazon SageMaker notebook instance with
the following features:

1. **Autostop Functionality**: Automatically stops the notebook instance when idle
   for a specified duration outside of active hours.
2. **VSCode Server (code-server)**: Allows you to run and access VSCode in the
   browser with HTTPS security.

## Repository Structure

```bash
my-sagemaker-setup/
├── autostop/
│   ├── autostop.py          # Main autostop script
│   ├── autostop_config.env  # Configuration file for autostop
│   └── setup_autostop.sh    # Shell script to install autostop dependencies
├── code-server/
│   └── setup_code_server.sh # Shell script to install code-server
├── lifecycle_configurations/
│   ├── on-create.sh        # One-time setup script
│   └── on-start.sh         # Runs on every start
└── README.md               # This file
```

## Prerequisites

- An AWS account with permissions to create and manage SageMaker notebook instances.
- An IAM role with the following permissions:
  - `sagemaker:StopNotebookInstance`
  - `sagemaker:DescribeNotebookInstance`
- Basic knowledge of AWS SageMaker and lifecycle configurations.

## Features

### Autostop Features

- **Idle Detection**: Automatically shuts down the SageMaker notebook instance
  after a configurable idle period.
- **CPU Usage Monitoring**: Tracks CPU usage and only considers the notebook idle
  when CPU usage is below a configurable threshold.
- **Active Hours and Days**: Prevents the instance from shutting down during
  configured active hours or days (e.g., Monday to Friday, 8 AM to 7:30 PM).

### Code-Server (VSCode in the Browser)

- **Password-Protected**: Automatically generates a secure password during instance
  creation.
- **HTTPS Access**: Configures `code-server` with HTTPS using self-signed
  certificates (or you can replace with a valid SSL certificate).
- **Nginx Reverse Proxy**: Configures Nginx as a reverse proxy for `code-server`,
  providing secure browser-based access.

## Setup Instructions

### Step 1: Clone the Repository

Clone this repository to your local machine:

```bash
git clone https://github.com/your-username/my-sagemaker-setup.git
```

### Step 2: Modify Configuration Files

#### Autostop Configuration

1. Navigate to `autostop/autostop_config.env`.
2. Modify the parameters as needed:
   - **IDLE_TIME**: Idle time (in seconds) before the notebook instance should be stopped.
   - **CPU_THRESHOLD**: Minimum CPU usage threshold to consider the instance idle.
   - **START_HOUR** and **END_HOUR**: Active hours during which the instance should not be stopped.

#### Code-Server Configuration

1. The `on-create.sh` script generates a secure password for code-server during instance creation.
2. The password is logged to `/home/ec2-user/SageMaker/code-server-password.txt`. Make sure to retrieve this password if you want to access code-server from your browser.

### Step 3: Upload Files to SageMaker

1. Open your SageMaker notebook instance or create a new one.
2. Upload the entire repository to `/home/ec2-user/SageMaker/my-sagemaker-setup/` on the instance.

### Step 4: Set Up Lifecycle Configuration

#### Create Lifecycle Configuration Scripts

1. Go to the AWS Management Console > **Amazon SageMaker** > **Lifecycle configurations**.
2. Create a new lifecycle configuration named `autostop-and-code-server`.

##### **On-Create Script**

- In the **Creation script** section, add the content of `lifecycle_configurations/on-create.sh`.

##### **On-Start Script**

- In the **Start script** section, add the content of `lifecycle_configurations/on-start.sh`.

#### Attach the Lifecycle Configuration to the Notebook Instance

1. Navigate to **Notebook instances** in the AWS Management Console.
2. Select your notebook instance and click on **Actions** > **Edit**.
3. Under **Lifecycle configuration**, select `autostop-and-code-server`.
4. Save the changes.

### Step 5: Restart the Notebook Instance

If the notebook instance is running, stop it and then start it again to apply the lifecycle configuration.

### Step 6: Verify the Setup

#### Autostop Functionality

- The autostop script should now be running and monitoring the notebook instance.
- Check `/var/log/autostop.log` for logs:

  ```bash
  cat /var/log/autostop.log
  ```

#### Access Code-Server

1. Retrieve the password for `code-server` from the log file:

   ```bash
   cat /home/ec2-user/SageMaker/code-server-password.txt
   ```

2. Retrieve the public DNS of your instance and use it to access code-server:

   ```bash
   cat /var/log/jupyter.log | grep "VSCode is running at"
   ```

3. Open the URL (e.g., `https://your-instance-public-dns`) in your browser and use the generated password to log in.

### Step 7: Security Considerations

- **SSL Certificates**: Replace self-signed certificates with trusted SSL certificates for production use.
- **Password Management**: Store passwords securely and ensure that the `code-server-password.txt` file is protected.
- **IP Whitelisting**: Limit access to trusted IP addresses using AWS Security Groups.

## Troubleshooting

- **Logs**:
  - Autostop logs: `/var/log/autostop.log`
  - Code-server logs: `/var/log/jupyter.log`
  - Nginx logs: `/var/log/nginx/error.log`

- **Service Status**:
  - Check the status of `code-server`:

    ```bash
    sudo systemctl status code-server
    ```

  - Check the status of Nginx:

    ```bash
    sudo systemctl status nginx
    ```

## Customization

You can customize the following features:

1. **Autostop Parameters**: Modify the idle time, active hours, and CPU thresholds in `autostop/autostop_config.env`.
2. **Code-Server Password**: The `on-create.sh` script automatically generates a secure password. You can modify this script if you prefer a different password generation method or want to use a fixed password.
3. **SSL Certificates**: Replace the self-signed certificates in `/opt/ml/certificates/` with trusted certificates if needed.


## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## Acknowledgments

- **Autostop**: This implementation was inspired by AWS lifecycle configuration best practices.
- **Code-Server**: `code-server` allows you to run Visual Studio Code in the browser, making it easier to work on remote instances with a familiar IDE.
