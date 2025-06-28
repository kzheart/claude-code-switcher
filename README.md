# Claude Code Account Manager

A macOS shell script for managing multiple Claude personal accounts using the macOS Keychain system. This tool allows you to seamlessly switch between different Claude Code accounts without having to log in and out manually each time.

## Features

- **Secure Credential Storage**: Uses macOS Keychain to securely store account credentials
- **Multiple Account Management**: Add, switch between, and delete multiple Claude accounts
- **Interactive & Command Line Interface**: Supports both interactive menu mode and direct command execution
- **Account Status Tracking**: View current login status and account information
- **Safe Account Switching**: Preserves all credential files when switching accounts

## Prerequisites

- macOS (this script is designed specifically for macOS)
- Claude Code CLI installed and configured
- `security` command (built into macOS)
- `jq` (optional but recommended for better JSON processing)

## Installation

1. Clone or download this repository
2. Make the script executable:
   ```bash
   chmod +x claude-account-manager-en.sh
   ```
3. (Optional) Install jq for better JSON handling:
   ```bash
   brew install jq
   ```

## Quick Start

### Quick Usage with curl (Interactive Mode)

You can quickly try the script without downloading using curl:

```bash
# Run directly in interactive mode
curl -s https://raw.githubusercontent.com/kzheart/claude-code-switcher/master/claude-account-manager-en.sh | bash -s - < /dev/tty

# Or download and run locally
curl -o claude-account-manager-en.sh https://raw.githubusercontent.com/kzheart/claude-code-switcher/master/claude-account-manager-en.sh && chmod +x claude-account-manager-en.sh && ./claude-account-manager-en.sh
```


## Usage

### Interactive Mode

Run the script without arguments to enter interactive mode:

```bash
./claude-account-manager-en.sh
```

This will present a menu with the following options:
1. Add account
2. Login account  
3. Logout
4. Account list
5. Delete account
6. Show status
7. Exit

### Command Line Mode

You can also use the script with direct commands:

#### Add a new account
```bash
# Interactive mode
./claude-account-manager-en.sh add

# With account name
./claude-account-manager-en.sh add work

# With account name and description
./claude-account-manager-en.sh add work "Work Account"
```

#### Login to an account
```bash
# Interactive selection
./claude-account-manager-en.sh login

# Login to specific account
./claude-account-manager-en.sh login work
```

#### List all accounts
```bash
./claude-account-manager-en.sh list
```

#### Show current status
```bash
./claude-account-manager-en.sh status
```

#### Logout from current account
```bash
./claude-account-manager-en.sh logout
```

#### Delete an account
```bash
# Interactive deletion
./claude-account-manager-en.sh delete

# Delete specific account (requires confirmation)
./claude-account-manager-en.sh delete work
```

#### Show help
```bash
./claude-account-manager-en.sh help
```

## How It Works

1. **Account Addition**: When you add an account, the script captures your current Claude Code credentials from the macOS Keychain and saves them to a secure file
2. **Account Switching**: When you switch accounts, the script replaces the current credentials in the Keychain with those from the selected account
3. **Secure Storage**: All credentials are stored in `~/.claude-accounts/` with secure file permissions (600/700)
4. **Configuration Management**: Account metadata is stored in JSON format for easy management

## File Structure

```
~/.claude-accounts/
├── config.json          # Account metadata and configuration
├── current.txt          # Currently active account name
└── accounts/
    ├── work.creds       # Credential files for each account
    ├── personal.creds
    └── ...
```

## Security Notes

- All credential files are stored with secure permissions (600)
- The account management directory has restricted access (700)
- Credentials are stored locally on your machine only
- The script uses macOS Keychain, which is encrypted and secure

## Troubleshooting

### "Error: This script only supports macOS"
This script is designed specifically for macOS and uses macOS-specific commands like `security`.

### "Error: security command not found"
The `security` command should be built into macOS. If it's missing, your macOS installation may be incomplete.

### "Warning: jq command not found"
While not required, `jq` provides better JSON processing. Install it with: `brew install jq`

### "Error: Unable to get current credentials"
Make sure you're logged into Claude Code before adding an account. Run `claude-code auth login` first.

### Account switching not working
After switching accounts, you need to restart Claude Code for the changes to take effect.

## Important Notes

- **Restart Required**: You must restart Claude Code after switching accounts for changes to take effect
- **Account Names**: Account names can only contain letters, numbers, underscores, and hyphens
- **Backup**: Consider backing up your `~/.claude-accounts/` directory for account recovery
- **Single Machine**: This tool manages accounts locally on a single machine only

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.
