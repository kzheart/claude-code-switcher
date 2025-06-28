#!/bin/bash

# Claude Code Multi-Account Manager for macOS
# Manages multiple personal Claude accounts using macOS Keychain

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
ACCOUNTS_DIR="$HOME/.claude-accounts"
CONFIG_FILE="$ACCOUNTS_DIR/config.json"
CURRENT_FILE="$ACCOUNTS_DIR/current.txt"
CREDS_DIR="$ACCOUNTS_DIR/accounts"
KEYCHAIN_SERVICE="Claude Code-credentials"

echo -e "${BLUE}=== Claude Code Multi-Account Manager ===${NC}"
echo

# Function to check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo -e "${RED}Error: This script only supports macOS${NC}"
        echo -e "Script uses macOS Keychain to manage Claude Code credentials"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    if ! command -v security &> /dev/null; then
        echo -e "${RED}Error: security command not found${NC}"
        echo -e "This script requires the macOS security command"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq command not found, will use basic JSON processing${NC}"
        echo -e "Recommended to install jq: brew install jq"
    fi
}

# Function to ensure directory structure exists
setup_directories() {
    if [ ! -d "$ACCOUNTS_DIR" ]; then
        echo -e "${BLUE}Creating account management directory: $ACCOUNTS_DIR${NC}"
        if mkdir -p "$ACCOUNTS_DIR"; then
            echo -e "${GREEN}✓ Account management directory created${NC}"
        else
            echo -e "${RED}✗ Failed to create account management directory${NC}"
            exit 1
        fi
    fi
    
    if [ ! -d "$CREDS_DIR" ]; then
        echo -e "${BLUE}Creating credentials storage directory: $CREDS_DIR${NC}"
        if mkdir -p "$CREDS_DIR"; then
            echo -e "${GREEN}✓ Credentials storage directory created${NC}"
        else
            echo -e "${RED}✗ Failed to create credentials storage directory${NC}"
            exit 1
        fi
    fi
    
    # Set secure permissions
    if chmod 700 "$ACCOUNTS_DIR" && chmod 700 "$CREDS_DIR"; then
        echo -e "${GREEN}✓ Secure directory permissions set${NC}"
    else
        echo -e "${RED}✗ Failed to set directory permissions${NC}"
        exit 1
    fi
    
    # Initialize config file if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"accounts": {}}' > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo -e "${GREEN}✓ Configuration file initialized${NC}"
    fi
    
    # Initialize current file if it doesn't exist
    if [ ! -f "$CURRENT_FILE" ]; then
        echo "" > "$CURRENT_FILE"
        chmod 600 "$CURRENT_FILE"
        echo -e "${GREEN}✓ Current account file initialized${NC}"
    fi
}

# Function to get current timestamp in ISO format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Function to validate account name
validate_account_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error: Account name can only contain letters, numbers, underscores and hyphens${NC}"
        return 1
    fi
    if [ ${#name} -gt 50 ]; then
        echo -e "${RED}Error: Account name cannot exceed 50 characters${NC}"
        return 1
    fi
    return 0
}

# Function to read JSON config with fallback for systems without jq
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{}"
        return
    fi
    
    if command -v jq &> /dev/null; then
        jq . "$CONFIG_FILE" 2>/dev/null || echo "{}"
    else
        cat "$CONFIG_FILE" 2>/dev/null || echo "{}"
    fi
}

# Function to update account config
update_account_config() {
    local account_name="$1"
    local description="$2"
    local timestamp=$(get_timestamp)
    
    # Read current config
    local current_config=$(read_config)
    
    if command -v jq &> /dev/null; then
        # Use jq for precise JSON manipulation
        echo "$current_config" | jq --arg name "$account_name" \
                                    --arg desc "$description" \
                                    --arg time "$timestamp" \
                                    '.accounts[$name] = {
                                        "description": $desc,
                                        "created": (if .accounts[$name].created then .accounts[$name].created else $time end),
                                        "last_used": $time
                                    }' > "$CONFIG_FILE"
    else
        # Basic JSON manipulation without jq
        local temp_file=$(mktemp)
        cat > "$temp_file" << EOF
{
  "accounts": {
    "$account_name": {
      "description": "$description",
      "created": "$timestamp",
      "last_used": "$timestamp"
    }
  }
}
EOF
        mv "$temp_file" "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"
}

# Function to remove account from config
remove_account_config() {
    local account_name="$1"
    
    if command -v jq &> /dev/null; then
        local current_config=$(read_config)
        echo "$current_config" | jq --arg name "$account_name" 'del(.accounts[$name])' > "$CONFIG_FILE"
    else
        # Without jq, recreate config without the account
        echo '{"accounts": {}}' > "$CONFIG_FILE"
    fi
    
    chmod 600 "$CONFIG_FILE"
}

# Function to get current account from file
get_current_account() {
    if [ -f "$CURRENT_FILE" ]; then
        cat "$CURRENT_FILE" 2>/dev/null | tr -d '\n' | tr -d ' '
    else
        echo ""
    fi
}

# Function to set current account
set_current_account() {
    local account_name="$1"
    echo "$account_name" > "$CURRENT_FILE"
    chmod 600 "$CURRENT_FILE"
}

# Function to get credentials from keychain
get_keychain_credentials() {
    local error_output
    local exit_code
    
    error_output=$(security find-generic-password -a "$USER" -w -s "$KEYCHAIN_SERVICE" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo "$error_output"
        return 0
    else
        echo -e "${RED}✗ Unable to get credentials from keychain${NC}" >&2
        echo -e "${RED}Exit code: $exit_code${NC}" >&2
        echo -e "${RED}Error message: $error_output${NC}" >&2
        return 1
    fi
}

# Function to set credentials in keychain
set_keychain_credentials() {
    local creds="$1"
    
    # Delete existing entries first
    security delete-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" 2>/dev/null || true
    
    # Add new credentials
    local add_output
    add_output=$(security add-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" -w "$creds" 2>&1)
    local add_exit_code=$?
    
    if [ $add_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Credentials successfully stored to keychain${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to store credentials to keychain${NC}"
        echo -e "${RED}Exit code: $add_exit_code${NC}"
        echo -e "${RED}Error message: $add_output${NC}"
        return 1
    fi
}

# Function to delete credentials from keychain
delete_keychain_credentials() {
    local delete_output
    delete_output=$(security delete-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" 2>&1)
    local delete_exit_code=$?
    
    if [ $delete_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ Credentials deleted from keychain${NC}"
        return 0
    else
        if [[ "$delete_output" =~ "could not be found" ]]; then
            echo -e "${YELLOW}ℹ No credentials found in keychain${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to delete credentials from keychain${NC}"
            echo -e "${RED}Exit code: $delete_exit_code${NC}"
            echo -e "${RED}Error message: $delete_output${NC}"
            return 1
        fi
    fi
}

# Function to save credentials to file
save_credentials_to_file() {
    local creds="$1"
    local account_name="$2"
    local creds_file="$CREDS_DIR/$account_name.creds"
    
    if echo "$creds" > "$creds_file"; then
        if chmod 600 "$creds_file"; then
            echo -e "${GREEN}✓ Credentials saved to $creds_file${NC}"
            return 0
        else
            echo -e "${RED}✗ Failed to set credentials file permissions${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ Failed to write credentials file${NC}"
        return 1
    fi
}

# Function to load credentials from file
load_credentials_from_file() {
    local account_name="$1"
    local creds_file="$CREDS_DIR/$account_name.creds"
    
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}✗ Credentials file for account '$account_name' does not exist${NC}"
        return 1
    fi
    
    local creds
    creds=$(cat "$creds_file") || {
        echo -e "${RED}✗ Failed to read credentials file${NC}"
        return 1
    }
    
    echo "$creds"
    return 0
}

# Function to add a new account
add_account() {
    local account_name="$1"
    local description="$2"
    
    # Validate account name
    if ! validate_account_name "$account_name"; then
        return 1
    fi
    
    # Check if account already exists
    local creds_file="$CREDS_DIR/$account_name.creds"
    if [ -f "$creds_file" ]; then
        echo -e "${YELLOW}Account '$account_name' already exists${NC}"
        read -p "Do you want to overwrite the existing account? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Operation cancelled${NC}"
            return 1
        fi
    fi
    
    echo -e "${BLUE}Getting current credentials from keychain...${NC}"
    
    # Get current credentials from keychain
    local current_creds
    current_creds=$(get_keychain_credentials) || {
        echo -e "${RED}Error: Unable to get current credentials${NC}"
        echo -e "${YELLOW}Please ensure you are logged into Claude Code${NC}"
        return 1
    }
    
    # Save credentials to file
    save_credentials_to_file "$current_creds" "$account_name" || {
        echo -e "${RED}Failed to save credentials${NC}"
        return 1
    }
    
    # Update config
    update_account_config "$account_name" "$description"
    
    # Set as current account
    set_current_account "$account_name"
    
    echo -e "${GREEN}✓ Account '$account_name' added successfully${NC}"
    echo -e "${GREEN}✓ Set as current active account${NC}"
    
    return 0
}

# Interactive function to add account with prompts
add_account_interactive() {
    echo -e "${CYAN}=== Add New Account ===${NC}"
    echo
    
    # Get account name
    while true; do
        read -p "Enter account name (letters, numbers, underscores, hyphens): " account_name
        if [ -z "$account_name" ]; then
            echo -e "${RED}Account name cannot be empty${NC}"
            continue
        fi
        if validate_account_name "$account_name"; then
            break
        fi
    done
    
    # Get description
    read -p "Enter account description (optional): " description
    if [ -z "$description" ]; then
        description="Claude Account"
    fi
    
    echo
    echo -e "${YELLOW}Ready to add account:${NC}"
    echo -e "  Name: $account_name"
    echo -e "  Description: $description"
    echo
    
    read -p "Confirm addition? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}Operation cancelled${NC}"
        return 1
    fi
    
    add_account "$account_name" "$description"
}

# Function to login to an account
login_account() {
    local account_name="$1"
    
    if [ -z "$account_name" ]; then
        echo -e "${RED}Error: No account name specified${NC}"
        return 1
    fi
    
    # Validate account name
    if ! validate_account_name "$account_name"; then
        return 1
    fi
    
    # Check if account exists
    local creds_file="$CREDS_DIR/$account_name.creds"
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}Error: Account '$account_name' does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Logging in to account '$account_name'...${NC}"
    
    # Load credentials from file
    local creds
    creds=$(load_credentials_from_file "$account_name") || {
        echo -e "${RED}Failed to load credentials${NC}"
        return 1
    }
    
    # Set credentials in keychain
    set_keychain_credentials "$creds" || {
        echo -e "${RED}Login failed${NC}"
        return 1
    }
    
    # Update current account and last used time
    set_current_account "$account_name"
    local config=$(read_config)
    if command -v jq &> /dev/null; then
        local timestamp=$(get_timestamp)
        echo "$config" | jq --arg name "$account_name" --arg time "$timestamp" \
            '.accounts[$name].last_used = $time' > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Successfully logged in to account '$account_name'${NC}"
    echo -e "${YELLOW}Note: Restart Claude Code for changes to take effect${NC}"
    
    return 0
}

# Interactive function to login
login_account_interactive() {
    echo -e "${CYAN}=== Account Login ===${NC}"
    echo
    
    # List available accounts
    echo -e "${BLUE}Available accounts:${NC}"
    local accounts_found=false
    local counter=1
    local account_names=()
    
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            account_names+=("$account_name")
            
            # Get description from config
            local description="No description"
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "No description"')
            fi
            
            echo -e "  $counter. $account_name - $description"
            ((counter++))
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}No saved accounts found${NC}"
        echo -e "${BLUE}Please use 'add' command to add an account first${NC}"
        return 1
    fi
    
    echo
    
    # Get user choice
    while true; do
        read -p "Select account (enter number or account name): " choice
        
        if [ -z "$choice" ]; then
            echo -e "${RED}Please enter a valid selection${NC}"
            continue
        fi
        
        # Check if it's a number
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#account_names[@]}" ]; then
                local selected_account="${account_names[$((choice-1))]}"
                login_account "$selected_account"
                return $?
            else
                echo -e "${RED}Invalid number${NC}"
                continue
            fi
        else
            # Check if it's a valid account name
            local found=false
            for account in "${account_names[@]}"; do
                if [ "$account" = "$choice" ]; then
                    found=true
                    login_account "$choice"
                    return $?
                fi
            done
            
            if [ "$found" = false ]; then
                echo -e "${RED}Account '$choice' does not exist${NC}"
                continue
            fi
        fi
    done
}

# Function to logout (clear keychain but keep files)
logout_account() {
    echo -e "${BLUE}Logging out...${NC}"
    
    # Delete credentials from keychain
    delete_keychain_credentials || {
        echo -e "${RED}Logout failed${NC}"
        return 1
    }
    
    # Clear current account
    set_current_account ""
    
    echo -e "${GREEN}✓ Successfully logged out${NC}"
    echo -e "${YELLOW}All account credential files are kept, you can use 'login' command to log in again${NC}"
    
    return 0
}

# Interactive function to logout with confirmation
logout_account_interactive() {
    echo -e "${CYAN}=== Account Logout ===${NC}"
    echo
    
    local current_account=$(get_current_account)
    if [ -z "$current_account" ]; then
        echo -e "${YELLOW}No account is currently logged in${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Currently logged in account: $current_account${NC}"
    echo -e "${YELLOW}Logging out will clear authentication information from keychain, but keep all credential files${NC}"
    echo
    
    read -p "Confirm logout? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Operation cancelled${NC}"
        return 1
    fi
    
    logout_account
}

# Function to list all accounts
list_accounts() {
    echo -e "${CYAN}=== Account List ===${NC}"
    echo
    
    local accounts_found=false
    local current_account=$(get_current_account)
    
    # Check for account files
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            
            # Get account info from config
            local description="No description"
            local created="Unknown"
            local last_used="Never used"
            
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "No description"')
                created=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].created // "Unknown"')
                last_used=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].last_used // "Never used"')
                
                # Format dates if they're ISO format
                if [[ "$created" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
                    created=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created")
                fi
                if [[ "$last_used" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
                    last_used=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_used" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_used")
                fi
            fi
            
            # Check if this is the current account
            local status_indicator=""
            if [ "$account_name" = "$current_account" ]; then
                status_indicator=" ${GREEN}[Current]${NC}"
            fi
            
            echo -e "${BLUE}Account:${NC} $account_name$status_indicator"
            echo -e "  ${YELLOW}Description:${NC} $description"
            echo -e "  ${YELLOW}Created:${NC} $created"
            echo -e "  ${YELLOW}Last used:${NC} $last_used"
            
            # Show file info
            local file_size=$(stat -f%z "$creds_file" 2>/dev/null || echo "Unknown")
            echo -e "  ${YELLOW}Credentials file:${NC} $creds_file ($file_size bytes)"
            echo
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}No saved accounts found${NC}"
        echo -e "${BLUE}Use 'add' command to add a new account${NC}"
    else
        echo -e "${BLUE}Use 'login <account_name>' to switch accounts${NC}"
        echo -e "${BLUE}Use 'delete <account_name>' to delete an account${NC}"
    fi
    
    return 0
}

# Function to delete an account
delete_account() {
    local account_name="$1"
    
    if [ -z "$account_name" ]; then
        echo -e "${RED}Error: No account name specified${NC}"
        return 1
    fi
    
    # Validate account name
    if ! validate_account_name "$account_name"; then
        return 1
    fi
    
    # Check if account exists
    local creds_file="$CREDS_DIR/$account_name.creds"
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}Error: Account '$account_name' does not exist${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Deleting account '$account_name'...${NC}"
    
    # Check if this is the current account
    local current_account=$(get_current_account)
    if [ "$account_name" = "$current_account" ]; then
        echo -e "${YELLOW}Warning: This is the currently logged in account, you will be logged out after deletion${NC}"
    fi
    
    # Remove credentials file
    if rm -f "$creds_file"; then
        echo -e "${GREEN}✓ Credentials file deleted${NC}"
    else
        echo -e "${RED}✗ Failed to delete credentials file${NC}"
        return 1
    fi
    
    # Remove from config
    remove_account_config "$account_name"
    echo -e "${GREEN}✓ Removed from configuration${NC}"
    
    # If this was the current account, logout
    if [ "$account_name" = "$current_account" ]; then
        delete_keychain_credentials
        set_current_account ""
        echo -e "${GREEN}✓ Automatically logged out${NC}"
    fi
    
    echo -e "${GREEN}✓ Account '$account_name' deleted successfully${NC}"
    
    return 0
}

# Interactive function to delete account with confirmation
delete_account_interactive() {
    echo -e "${CYAN}=== Delete Account ===${NC}"
    echo
    
    # List available accounts
    echo -e "${BLUE}Available accounts:${NC}"
    local accounts_found=false
    local counter=1
    local account_names=()
    
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            account_names+=("$account_name")
            
            # Get description from config
            local description="No description"
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "No description"')
            fi
            
            # Check if current
            local current_account=$(get_current_account)
            local current_indicator=""
            if [ "$account_name" = "$current_account" ]; then
                current_indicator=" ${GREEN}[Current]${NC}"
            fi
            
            echo -e "  $counter. $account_name - $description$current_indicator"
            ((counter++))
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}No saved accounts found${NC}"
        return 1
    fi
    
    echo
    
    # Get user choice
    while true; do
        read -p "Select account to delete (enter number or account name): " choice
        
        if [ -z "$choice" ]; then
            echo -e "${RED}Please enter a valid selection${NC}"
            continue
        fi
        
        local selected_account=""
        
        # Check if it's a number
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#account_names[@]}" ]; then
                selected_account="${account_names[$((choice-1))]}"
            else
                echo -e "${RED}Invalid number${NC}"
                continue
            fi
        else
            # Check if it's a valid account name
            local found=false
            for account in "${account_names[@]}"; do
                if [ "$account" = "$choice" ]; then
                    found=true
                    selected_account="$choice"
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                echo -e "${RED}Account '$choice' does not exist${NC}"
                continue
            fi
        fi
        
        # Confirm deletion
        echo
        echo -e "${RED}Warning: This will permanently delete all data for account '$selected_account'${NC}"
        echo -e "${RED}Including credential files and configuration information, this action is irreversible${NC}"
        echo
        
        read -p "Confirm deletion of account '$selected_account'? (type 'DELETE' to confirm): " confirm
        if [ "$confirm" = "DELETE" ]; then
            delete_account "$selected_account"
            return $?
        else
            echo -e "${BLUE}Operation cancelled${NC}"
            return 1
        fi
    done
}

# Function to show current status
show_status() {
    echo -e "${CYAN}=== Current Status ===${NC}"
    echo
    
    # Check keychain status
    echo -e "${BLUE}Keychain Status:${NC}"
    if get_keychain_credentials > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Claude Code credentials found${NC}"
        
        # Try to determine credential type
        local creds
        creds=$(get_keychain_credentials 2>/dev/null)
        if [[ "$creds" =~ ^\{ ]]; then
            echo -e "  ${YELLOW}Type:${NC} Personal account credentials (JSON format)"
        else
            echo -e "  ${YELLOW}Type:${NC} API key or other format"
        fi
    else
        echo -e "  ${RED}✗ Claude Code credentials not found${NC}"
    fi
    
    echo
    
    # Check current account
    local current_account=$(get_current_account)
    echo -e "${BLUE}Current Account:${NC}"
    if [ -n "$current_account" ]; then
        echo -e "  ${GREEN}$current_account${NC}"
        
        # Get account details
        if command -v jq &> /dev/null; then
            local config=$(read_config)
            local description=$(echo "$config" | jq -r --arg name "$current_account" '.accounts[$name].description // "No description"')
            local last_used=$(echo "$config" | jq -r --arg name "$current_account" '.accounts[$name].last_used // "Never used"')
            
            if [[ "$last_used" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
                last_used=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_used" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_used")
            fi
            
            echo -e "  ${YELLOW}Description:${NC} $description"
            echo -e "  ${YELLOW}Last used:${NC} $last_used"
        fi
    else
        echo -e "  ${YELLOW}None (logged out)${NC}"
    fi
    
    echo
    
    # Account summary
    echo -e "${BLUE}Account Summary:${NC}"
    local total_accounts=0
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            ((total_accounts++))
        fi
    done
    
    echo -e "  ${YELLOW}Saved accounts count:${NC} $total_accounts"
    
    if [ $total_accounts -gt 0 ]; then
        echo -e "  ${YELLOW}Storage location:${NC} $CREDS_DIR"
        echo -e "  ${YELLOW}Configuration file:${NC} $CONFIG_FILE"
    fi
    
    echo
    
    # System info
    echo -e "${BLUE}System Information:${NC}"
    echo -e "  ${YELLOW}User:${NC} $USER"
    echo -e "  ${YELLOW}Keychain service:${NC} $KEYCHAIN_SERVICE"
    
    # Check jq availability
    if command -v jq &> /dev/null; then
        echo -e "  ${YELLOW}JSON processing:${NC} ${GREEN}jq available${NC}"
    else
        echo -e "  ${YELLOW}JSON processing:${NC} ${YELLOW}Basic mode (recommend installing jq)${NC}"
    fi
    
    return 0
}

# Function to show main menu
show_menu() {
    echo
    echo -e "${BLUE}Select operation:${NC}"
    echo -e "1. Add account (add)"
    echo -e "2. Login account (login)"
    echo -e "3. Logout (logout)"
    echo -e "4. Account list (list)"
    echo -e "5. Delete account (delete)"
    echo -e "6. Show status (status)"
    echo -e "7. Exit"
    echo
}

# Main interactive menu
main_menu() {
    while true; do
        show_menu
        read -p "Enter your choice (1-7): " choice
        
        case $choice in
            1)
                add_account_interactive
                ;;
            2)
                login_account_interactive
                ;;
            3)
                logout_account_interactive
                ;;
            4)
                list_accounts
                ;;
            5)
                delete_account_interactive
                ;;
            6)
                show_status
                ;;
            7)
                echo -e "${BLUE}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice, please try again${NC}"
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Function to show usage help
show_help() {
    echo -e "${CYAN}Usage:${NC}"
    echo -e "  $0 [command] [arguments]"
    echo
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${BLUE}add [account_name] [description]${NC}    - Add new account"
    echo -e "  ${BLUE}login [account_name]${NC}                - Login to specified account"
    echo -e "  ${BLUE}logout${NC}                              - Logout current account"
    echo -e "  ${BLUE}list${NC}                                - Show all accounts"
    echo -e "  ${BLUE}delete [account_name]${NC}               - Delete specified account"
    echo -e "  ${BLUE}status${NC}                              - Show current status"
    echo -e "  ${BLUE}help${NC}                                - Show this help information"
    echo
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  $0                         # Start interactive mode"
    echo -e "  $0 add work \"Work account\" # Add work account"
    echo -e "  $0 login work              # Login to work account"
    echo -e "  $0 list                    # Show account list"
    echo -e "  $0 logout                  # Logout"
    echo
    echo -e "${CYAN}Notes:${NC}"
    echo -e "  - Account names can only contain letters, numbers, underscores and hyphens"
    echo -e "  - Restart Claude Code for account switching to take effect"
    echo -e "  - All credentials are securely stored in ~/.claude-accounts/"
}

# Main execution starts here
check_macos
check_dependencies
setup_directories

# Command line argument processing
if [ $# -eq 0 ]; then
    # No arguments - start interactive mode
    main_menu
else
    # Handle command line arguments
    command="$1"
    
    case "$command" in
        "add")
            if [ $# -eq 1 ]; then
                add_account_interactive
            elif [ $# -eq 2 ]; then
                add_account "$2" "Claude Account"
            elif [ $# -eq 3 ]; then
                add_account "$2" "$3"
            else
                echo -e "${RED}Error: too many arguments for add command${NC}"
                echo -e "Usage: $0 add [account_name] [description]"
                exit 1
            fi
            ;;
        "login")
            if [ $# -eq 1 ]; then
                login_account_interactive
            elif [ $# -eq 2 ]; then
                login_account "$2"
            else
                echo -e "${RED}Error: too many arguments for login command${NC}"
                echo -e "Usage: $0 login [account_name]"
                exit 1
            fi
            ;;
        "logout")
            if [ $# -eq 1 ]; then
                logout_account
            else
                echo -e "${RED}Error: logout command does not accept arguments${NC}"
                echo -e "Usage: $0 logout"
                exit 1
            fi
            ;;
        "list")
            if [ $# -eq 1 ]; then
                list_accounts
            else
                echo -e "${RED}Error: list command does not accept arguments${NC}"
                echo -e "Usage: $0 list"
                exit 1
            fi
            ;;
        "delete")
            if [ $# -eq 1 ]; then
                delete_account_interactive
            elif [ $# -eq 2 ]; then
                # For command line deletion, require confirmation
                echo -e "${RED}Warning: This will permanently delete all data for account '$2'${NC}"
                read -p "Confirm deletion of account '$2'? (type 'DELETE' to confirm): " confirm
                if [ "$confirm" = "DELETE" ]; then
                    delete_account "$2"
                else
                    echo -e "${BLUE}Operation cancelled${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}Error: too many arguments for delete command${NC}"
                echo -e "Usage: $0 delete [account_name]"
                exit 1
            fi
            ;;
        "status")
            if [ $# -eq 1 ]; then
                show_status
            else
                echo -e "${RED}Error: status command does not accept arguments${NC}"
                echo -e "Usage: $0 status"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo -e "${RED}Error: unknown command '$command'${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
fi