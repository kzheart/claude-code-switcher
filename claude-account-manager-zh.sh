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
        echo -e "${RED}错误: 此脚本仅支持 macOS${NC}"
        echo -e "脚本使用 macOS Keychain 管理 Claude Code 凭证"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    if ! command -v security &> /dev/null; then
        echo -e "${RED}错误: 未找到 security 命令${NC}"
        echo -e "此脚本需要 macOS security 命令"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}警告: 未找到 jq 命令，将使用基础 JSON 处理${NC}"
        echo -e "建议安装 jq: brew install jq"
    fi
}

# Function to ensure directory structure exists
setup_directories() {
    if [ ! -d "$ACCOUNTS_DIR" ]; then
        echo -e "${BLUE}创建账号管理目录: $ACCOUNTS_DIR${NC}"
        if mkdir -p "$ACCOUNTS_DIR"; then
            echo -e "${GREEN}✓ 已创建账号管理目录${NC}"
        else
            echo -e "${RED}✗ 创建账号管理目录失败${NC}"
            exit 1
        fi
    fi
    
    if [ ! -d "$CREDS_DIR" ]; then
        echo -e "${BLUE}创建凭证存储目录: $CREDS_DIR${NC}"
        if mkdir -p "$CREDS_DIR"; then
            echo -e "${GREEN}✓ 已创建凭证存储目录${NC}"
        else
            echo -e "${RED}✗ 创建凭证存储目录失败${NC}"
            exit 1
        fi
    fi
    
    # Set secure permissions
    if chmod 700 "$ACCOUNTS_DIR" && chmod 700 "$CREDS_DIR"; then
        echo -e "${GREEN}✓ 已设置安全目录权限${NC}"
    else
        echo -e "${RED}✗ 设置目录权限失败${NC}"
        exit 1
    fi
    
    # Initialize config file if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"accounts": {}}' > "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
        echo -e "${GREEN}✓ 已初始化配置文件${NC}"
    fi
    
    # Initialize current file if it doesn't exist
    if [ ! -f "$CURRENT_FILE" ]; then
        echo "" > "$CURRENT_FILE"
        chmod 600 "$CURRENT_FILE"
        echo -e "${GREEN}✓ 已初始化当前账号文件${NC}"
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
        echo -e "${RED}错误: 账号名只能包含字母、数字、下划线和连字符${NC}"
        return 1
    fi
    if [ ${#name} -gt 50 ]; then
        echo -e "${RED}错误: 账号名长度不能超过50个字符${NC}"
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
        echo -e "${RED}✗ 无法从 keychain 获取凭证${NC}" >&2
        echo -e "${RED}退出代码: $exit_code${NC}" >&2
        echo -e "${RED}错误信息: $error_output${NC}" >&2
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
        echo -e "${GREEN}✓ 凭证已成功存储到 keychain${NC}"
        return 0
    else
        echo -e "${RED}✗ 存储凭证到 keychain 失败${NC}"
        echo -e "${RED}退出代码: $add_exit_code${NC}"
        echo -e "${RED}错误信息: $add_output${NC}"
        return 1
    fi
}

# Function to delete credentials from keychain
delete_keychain_credentials() {
    local delete_output
    delete_output=$(security delete-generic-password -a "$USER" -s "$KEYCHAIN_SERVICE" 2>&1)
    local delete_exit_code=$?
    
    if [ $delete_exit_code -eq 0 ]; then
        echo -e "${GREEN}✓ 已从 keychain 删除凭证${NC}"
        return 0
    else
        if [[ "$delete_output" =~ "could not be found" ]]; then
            echo -e "${YELLOW}ℹ Keychain 中没有找到凭证${NC}"
            return 0
        else
            echo -e "${RED}✗ 从 keychain 删除凭证失败${NC}"
            echo -e "${RED}退出代码: $delete_exit_code${NC}"
            echo -e "${RED}错误信息: $delete_output${NC}"
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
            echo -e "${GREEN}✓ 凭证已保存到 $creds_file${NC}"
            return 0
        else
            echo -e "${RED}✗ 设置凭证文件权限失败${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ 写入凭证文件失败${NC}"
        return 1
    fi
}

# Function to load credentials from file
load_credentials_from_file() {
    local account_name="$1"
    local creds_file="$CREDS_DIR/$account_name.creds"
    
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}✗ 账号 '$account_name' 的凭证文件不存在${NC}"
        return 1
    fi
    
    local creds
    creds=$(cat "$creds_file") || {
        echo -e "${RED}✗ 读取凭证文件失败${NC}"
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
        echo -e "${YELLOW}账号 '$account_name' 已存在${NC}"
        read -p "是否覆盖现有账号? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}操作已取消${NC}"
            return 1
        fi
    fi
    
    echo -e "${BLUE}正在从 keychain 获取当前凭证...${NC}"
    
    # Get current credentials from keychain
    local current_creds
    current_creds=$(get_keychain_credentials) || {
        echo -e "${RED}错误: 无法获取当前凭证${NC}"
        echo -e "${YELLOW}请确保已登录 Claude Code${NC}"
        return 1
    }
    
    # Save credentials to file
    save_credentials_to_file "$current_creds" "$account_name" || {
        echo -e "${RED}保存凭证失败${NC}"
        return 1
    }
    
    # Update config
    update_account_config "$account_name" "$description"
    
    # Set as current account
    set_current_account "$account_name"
    
    echo -e "${GREEN}✓ 账号 '$account_name' 添加成功${NC}"
    echo -e "${GREEN}✓ 已设置为当前活跃账号${NC}"
    
    return 0
}

# Interactive function to add account with prompts
add_account_interactive() {
    echo -e "${CYAN}=== 添加新账号 ===${NC}"
    echo
    
    # Get account name
    while true; do
        read -p "请输入账号名称 (字母、数字、下划线、连字符): " account_name
        if [ -z "$account_name" ]; then
            echo -e "${RED}账号名称不能为空${NC}"
            continue
        fi
        if validate_account_name "$account_name"; then
            break
        fi
    done
    
    # Get description
    read -p "请输入账号描述 (可选): " description
    if [ -z "$description" ]; then
        description="Claude 账号"
    fi
    
    echo
    echo -e "${YELLOW}准备添加账号:${NC}"
    echo -e "  名称: $account_name"
    echo -e "  描述: $description"
    echo
    
    read -p "确认添加? (Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return 1
    fi
    
    add_account "$account_name" "$description"
}

# Function to login to an account
login_account() {
    local account_name="$1"
    
    if [ -z "$account_name" ]; then
        echo -e "${RED}错误: 未指定账号名称${NC}"
        return 1
    fi
    
    # Validate account name
    if ! validate_account_name "$account_name"; then
        return 1
    fi
    
    # Check if account exists
    local creds_file="$CREDS_DIR/$account_name.creds"
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}错误: 账号 '$account_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${BLUE}正在登录账号 '$account_name'...${NC}"
    
    # Load credentials from file
    local creds
    creds=$(load_credentials_from_file "$account_name") || {
        echo -e "${RED}加载凭证失败${NC}"
        return 1
    }
    
    # Set credentials in keychain
    set_keychain_credentials "$creds" || {
        echo -e "${RED}登录失败${NC}"
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
    
    echo -e "${GREEN}✓ 已成功登录账号 '$account_name'${NC}"
    echo -e "${YELLOW}注意: 需要重启 Claude Code 使更改生效${NC}"
    
    return 0
}

# Interactive function to login
login_account_interactive() {
    echo -e "${CYAN}=== 账号登录 ===${NC}"
    echo
    
    # List available accounts
    echo -e "${BLUE}可用账号:${NC}"
    local accounts_found=false
    local counter=1
    local account_names=()
    
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            account_names+=("$account_name")
            
            # Get description from config
            local description="无描述"
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "无描述"')
            fi
            
            echo -e "  $counter. $account_name - $description"
            ((counter++))
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}没有找到已保存的账号${NC}"
        echo -e "${BLUE}请先使用 'add' 命令添加账号${NC}"
        return 1
    fi
    
    echo
    
    # Get user choice
    while true; do
        read -p "请选择账号 (输入编号或账号名): " choice
        
        if [ -z "$choice" ]; then
            echo -e "${RED}请输入有效选择${NC}"
            continue
        fi
        
        # Check if it's a number
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#account_names[@]}" ]; then
                local selected_account="${account_names[$((choice-1))]}"
                login_account "$selected_account"
                return $?
            else
                echo -e "${RED}无效的编号${NC}"
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
                echo -e "${RED}账号 '$choice' 不存在${NC}"
                continue
            fi
        fi
    done
}

# Function to logout (clear keychain but keep files)
logout_account() {
    echo -e "${BLUE}正在登出...${NC}"
    
    # Delete credentials from keychain
    delete_keychain_credentials || {
        echo -e "${RED}登出失败${NC}"
        return 1
    }
    
    # Clear current account
    set_current_account ""
    
    echo -e "${GREEN}✓ 已成功登出${NC}"
    echo -e "${YELLOW}所有账号凭证文件已保留，可使用 'login' 命令重新登录${NC}"
    
    return 0
}

# Interactive function to logout with confirmation
logout_account_interactive() {
    echo -e "${CYAN}=== 账号登出 ===${NC}"
    echo
    
    local current_account=$(get_current_account)
    if [ -z "$current_account" ]; then
        echo -e "${YELLOW}当前没有登录的账号${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}当前登录账号: $current_account${NC}"
    echo -e "${YELLOW}登出后将清除 keychain 中的认证信息，但保留所有凭证文件${NC}"
    echo
    
    read -p "确认登出? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}操作已取消${NC}"
        return 1
    fi
    
    logout_account
}

# Function to list all accounts
list_accounts() {
    echo -e "${CYAN}=== 账号列表 ===${NC}"
    echo
    
    local accounts_found=false
    local current_account=$(get_current_account)
    
    # Check for account files
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            
            # Get account info from config
            local description="无描述"
            local created="未知"
            local last_used="从未使用"
            
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "无描述"')
                created=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].created // "未知"')
                last_used=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].last_used // "从未使用"')
                
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
                status_indicator=" ${GREEN}[当前]${NC}"
            fi
            
            echo -e "${BLUE}账号:${NC} $account_name$status_indicator"
            echo -e "  ${YELLOW}描述:${NC} $description"
            echo -e "  ${YELLOW}创建时间:${NC} $created"
            echo -e "  ${YELLOW}最后使用:${NC} $last_used"
            
            # Show file info
            local file_size=$(stat -f%z "$creds_file" 2>/dev/null || echo "未知")
            echo -e "  ${YELLOW}凭证文件:${NC} $creds_file ($file_size 字节)"
            echo
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}没有找到已保存的账号${NC}"
        echo -e "${BLUE}使用 'add' 命令添加新账号${NC}"
    else
        echo -e "${BLUE}使用 'login <账号名>' 切换账号${NC}"
        echo -e "${BLUE}使用 'delete <账号名>' 删除账号${NC}"
    fi
    
    return 0
}

# Function to delete an account
delete_account() {
    local account_name="$1"
    
    if [ -z "$account_name" ]; then
        echo -e "${RED}错误: 未指定账号名称${NC}"
        return 1
    fi
    
    # Validate account name
    if ! validate_account_name "$account_name"; then
        return 1
    fi
    
    # Check if account exists
    local creds_file="$CREDS_DIR/$account_name.creds"
    if [ ! -f "$creds_file" ]; then
        echo -e "${RED}错误: 账号 '$account_name' 不存在${NC}"
        return 1
    fi
    
    echo -e "${BLUE}正在删除账号 '$account_name'...${NC}"
    
    # Check if this is the current account
    local current_account=$(get_current_account)
    if [ "$account_name" = "$current_account" ]; then
        echo -e "${YELLOW}警告: 这是当前登录的账号，删除后将自动登出${NC}"
    fi
    
    # Remove credentials file
    if rm -f "$creds_file"; then
        echo -e "${GREEN}✓ 已删除凭证文件${NC}"
    else
        echo -e "${RED}✗ 删除凭证文件失败${NC}"
        return 1
    fi
    
    # Remove from config
    remove_account_config "$account_name"
    echo -e "${GREEN}✓ 已从配置中移除${NC}"
    
    # If this was the current account, logout
    if [ "$account_name" = "$current_account" ]; then
        delete_keychain_credentials
        set_current_account ""
        echo -e "${GREEN}✓ 已自动登出${NC}"
    fi
    
    echo -e "${GREEN}✓ 账号 '$account_name' 删除完成${NC}"
    
    return 0
}

# Interactive function to delete account with confirmation
delete_account_interactive() {
    echo -e "${CYAN}=== 删除账号 ===${NC}"
    echo
    
    # List available accounts
    echo -e "${BLUE}可用账号:${NC}"
    local accounts_found=false
    local counter=1
    local account_names=()
    
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            accounts_found=true
            local account_name=$(basename "$creds_file" .creds)
            account_names+=("$account_name")
            
            # Get description from config
            local description="无描述"
            if command -v jq &> /dev/null; then
                local config=$(read_config)
                description=$(echo "$config" | jq -r --arg name "$account_name" '.accounts[$name].description // "无描述"')
            fi
            
            # Check if current
            local current_account=$(get_current_account)
            local current_indicator=""
            if [ "$account_name" = "$current_account" ]; then
                current_indicator=" ${GREEN}[当前]${NC}"
            fi
            
            echo -e "  $counter. $account_name - $description$current_indicator"
            ((counter++))
        fi
    done
    
    if [ "$accounts_found" = false ]; then
        echo -e "${YELLOW}没有找到已保存的账号${NC}"
        return 1
    fi
    
    echo
    
    # Get user choice
    while true; do
        read -p "请选择要删除的账号 (输入编号或账号名): " choice
        
        if [ -z "$choice" ]; then
            echo -e "${RED}请输入有效选择${NC}"
            continue
        fi
        
        local selected_account=""
        
        # Check if it's a number
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [ "$choice" -ge 1 ] && [ "$choice" -le "${#account_names[@]}" ]; then
                selected_account="${account_names[$((choice-1))]}"
            else
                echo -e "${RED}无效的编号${NC}"
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
                echo -e "${RED}账号 '$choice' 不存在${NC}"
                continue
            fi
        fi
        
        # Confirm deletion
        echo
        echo -e "${RED}警告: 这将永久删除账号 '$selected_account' 的所有数据${NC}"
        echo -e "${RED}包括凭证文件和配置信息，此操作不可撤销${NC}"
        echo
        
        read -p "确认删除账号 '$selected_account'? (输入 'DELETE' 确认): " confirm
        if [ "$confirm" = "DELETE" ]; then
            delete_account "$selected_account"
            return $?
        else
            echo -e "${BLUE}操作已取消${NC}"
            return 1
        fi
    done
}

# Function to show current status
show_status() {
    echo -e "${CYAN}=== 当前状态 ===${NC}"
    echo
    
    # Check keychain status
    echo -e "${BLUE}Keychain 状态:${NC}"
    if get_keychain_credentials > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ 发现 Claude Code 凭证${NC}"
        
        # Try to determine credential type
        local creds
        creds=$(get_keychain_credentials 2>/dev/null)
        if [[ "$creds" =~ ^\{ ]]; then
            echo -e "  ${YELLOW}类型:${NC} 个人账号凭证 (JSON 格式)"
        else
            echo -e "  ${YELLOW}类型:${NC} API 密钥或其他格式"
        fi
    else
        echo -e "  ${RED}✗ 未找到 Claude Code 凭证${NC}"
    fi
    
    echo
    
    # Check current account
    local current_account=$(get_current_account)
    echo -e "${BLUE}当前账号:${NC}"
    if [ -n "$current_account" ]; then
        echo -e "  ${GREEN}$current_account${NC}"
        
        # Get account details
        if command -v jq &> /dev/null; then
            local config=$(read_config)
            local description=$(echo "$config" | jq -r --arg name "$current_account" '.accounts[$name].description // "无描述"')
            local last_used=$(echo "$config" | jq -r --arg name "$current_account" '.accounts[$name].last_used // "从未使用"')
            
            if [[ "$last_used" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
                last_used=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$last_used" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$last_used")
            fi
            
            echo -e "  ${YELLOW}描述:${NC} $description"
            echo -e "  ${YELLOW}最后使用:${NC} $last_used"
        fi
    else
        echo -e "  ${YELLOW}无 (已登出状态)${NC}"
    fi
    
    echo
    
    # Account summary
    echo -e "${BLUE}账号摘要:${NC}"
    local total_accounts=0
    for creds_file in "$CREDS_DIR"/*.creds; do
        if [ -f "$creds_file" ]; then
            ((total_accounts++))
        fi
    done
    
    echo -e "  ${YELLOW}已保存账号数量:${NC} $total_accounts"
    
    if [ $total_accounts -gt 0 ]; then
        echo -e "  ${YELLOW}存储位置:${NC} $CREDS_DIR"
        echo -e "  ${YELLOW}配置文件:${NC} $CONFIG_FILE"
    fi
    
    echo
    
    # System info
    echo -e "${BLUE}系统信息:${NC}"
    echo -e "  ${YELLOW}用户:${NC} $USER"
    echo -e "  ${YELLOW}Keychain 服务:${NC} $KEYCHAIN_SERVICE"
    
    # Check jq availability
    if command -v jq &> /dev/null; then
        echo -e "  ${YELLOW}JSON 处理:${NC} ${GREEN}jq 可用${NC}"
    else
        echo -e "  ${YELLOW}JSON 处理:${NC} ${YELLOW}基础模式 (建议安装 jq)${NC}"
    fi
    
    return 0
}

# Function to show main menu
show_menu() {
    echo
    echo -e "${BLUE}选择操作:${NC}"
    echo -e "1. 添加账号 (add)"
    echo -e "2. 登录账号 (login)"
    echo -e "3. 登出 (logout)"
    echo -e "4. 账号列表 (list)"
    echo -e "5. 删除账号 (delete)"
    echo -e "6. 显示状态 (status)"
    echo -e "7. 退出"
    echo
}

# Main interactive menu
main_menu() {
    while true; do
        show_menu
        read -p "请输入选择 (1-7): " choice
        
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
                echo -e "${BLUE}再见!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                ;;
        esac
        
        echo
        read -p "按 Enter 继续..."
    done
}

# Function to show usage help
show_help() {
    echo -e "${CYAN}用法:${NC}"
    echo -e "  $0 [命令] [参数]"
    echo
    echo -e "${CYAN}命令:${NC}"
    echo -e "  ${BLUE}add [账号名] [描述]${NC}    - 添加新账号"
    echo -e "  ${BLUE}login [账号名]${NC}        - 登录指定账号"
    echo -e "  ${BLUE}logout${NC}               - 登出当前账号"
    echo -e "  ${BLUE}list${NC}                 - 显示所有账号"
    echo -e "  ${BLUE}delete [账号名]${NC}      - 删除指定账号"
    echo -e "  ${BLUE}status${NC}               - 显示当前状态"
    echo -e "  ${BLUE}help${NC}                 - 显示此帮助信息"
    echo
    echo -e "${CYAN}示例:${NC}"
    echo -e "  $0                      # 启动交互模式"
    echo -e "  $0 add work \"工作账号\" # 添加工作账号"
    echo -e "  $0 login work           # 登录工作账号"
    echo -e "  $0 list                 # 显示账号列表"
    echo -e "  $0 logout               # 登出"
    echo
    echo -e "${CYAN}注意:${NC}"
    echo -e "  - 账号名只能包含字母、数字、下划线和连字符"
    echo -e "  - 需要重启 Claude Code 使账号切换生效"
    echo -e "  - 所有凭证都安全存储在 ~/.claude-accounts/"
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
                add_account "$2" "Claude 账号"
            elif [ $# -eq 3 ]; then
                add_account "$2" "$3"
            else
                echo -e "${RED}错误: add 命令参数过多${NC}"
                echo -e "用法: $0 add [账号名] [描述]"
                exit 1
            fi
            ;;
        "login")
            if [ $# -eq 1 ]; then
                login_account_interactive
            elif [ $# -eq 2 ]; then
                login_account "$2"
            else
                echo -e "${RED}错误: login 命令参数过多${NC}"
                echo -e "用法: $0 login [账号名]"
                exit 1
            fi
            ;;
        "logout")
            if [ $# -eq 1 ]; then
                logout_account
            else
                echo -e "${RED}错误: logout 命令不接受参数${NC}"
                echo -e "用法: $0 logout"
                exit 1
            fi
            ;;
        "list")
            if [ $# -eq 1 ]; then
                list_accounts
            else
                echo -e "${RED}错误: list 命令不接受参数${NC}"
                echo -e "用法: $0 list"
                exit 1
            fi
            ;;
        "delete")
            if [ $# -eq 1 ]; then
                delete_account_interactive
            elif [ $# -eq 2 ]; then
                # For command line deletion, require confirmation
                echo -e "${RED}警告: 这将永久删除账号 '$2' 的所有数据${NC}"
                read -p "确认删除账号 '$2'? (输入 'DELETE' 确认): " confirm
                if [ "$confirm" = "DELETE" ]; then
                    delete_account "$2"
                else
                    echo -e "${BLUE}操作已取消${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}错误: delete 命令参数过多${NC}"
                echo -e "用法: $0 delete [账号名]"
                exit 1
            fi
            ;;
        "status")
            if [ $# -eq 1 ]; then
                show_status
            else
                echo -e "${RED}错误: status 命令不接受参数${NC}"
                echo -e "用法: $0 status"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$command'${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
fi