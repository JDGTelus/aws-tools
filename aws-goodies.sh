#!/bin/bash

# AWS Goodies - AWS Profile and Formatting Management Utility
# Version: 2.1.0
# Save as ~/.aws/aws-goodies.sh and source it in your ~/.bashrc or ~/.zshrc:
# source ~/.aws/aws-goodies.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Debug mode (set to true for verbose output)
DEBUG=false

# Timeout for AWS commands (in seconds)
AWS_TIMEOUT=30

# Cache settings
CACHE_DIR="${HOME}/.aws-goodies-cache"
CACHE_TTL=300  # 5 minutes in seconds

# Debug function
debug() {
    if [ "$DEBUG" = true ]; then
        echo -e "${YELLOW}DEBUG: $1${NC}" >&2
        if [ -n "$2" ]; then
            echo -e "${YELLOW}Output:${NC}\n$2" >&2
        fi
    fi
}

###########################################
# Utility Functions
###########################################

# Run command with timeout (macOS compatible)
# Since 'timeout' is not available on macOS by default, we skip timeout for macOS
_ag_run_with_timeout() {
    local timeout_seconds="$1"
    shift
    
    # Check if GNU timeout is available (from coreutils via brew)
    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "$timeout_seconds" "$@"
    elif command -v timeout >/dev/null 2>&1; then
        timeout "$timeout_seconds" "$@"
    else
        # No timeout available on macOS, just run the command
        debug "No timeout command available, running without timeout"
        "$@"
    fi
}

###########################################
# Dependency Checks
###########################################

# Check if required commands are available
_ag_check_dependencies() {
    local missing_deps=()
    
    command -v aws >/dev/null 2>&1 || missing_deps+=("aws-cli")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    command -v column >/dev/null 2>&1 || missing_deps+=("column")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}" >&2
        echo -e "${YELLOW}Please install the missing tools to use aws-goodies${NC}" >&2
        return 1
    fi
    
    return 0
}

# Validate that a profile exists
_ag_validate_profile() {
    local profile="$1"
    if [ -z "$profile" ]; then
        return 1
    fi
    
    if aws configure list-profiles 2>/dev/null | grep -q "^${profile}$"; then
        return 0
    else
        return 1
    fi
}

###########################################
# Cache Management
###########################################

# Initialize cache directory
_ag_init_cache() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
    fi
}

# Get cached value if valid
_ag_get_cache() {
    local cache_key="$1"
    local cache_file="${CACHE_DIR}/${cache_key}"
    
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    # Check if cache is still valid
    local cache_age=$(( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$cache_age" -gt "$CACHE_TTL" ]; then
        rm -f "$cache_file" 2>/dev/null || true
        return 1
    fi
    
    cat "$cache_file"
    return 0
}

# Set cache value
_ag_set_cache() {
    local cache_key="$1"
    local value="$2"
    local cache_file="${CACHE_DIR}/${cache_key}"
    
    _ag_init_cache
    echo "$value" > "$cache_file" 2>/dev/null || true
}

# Clear all cache
_ag_clear_cache() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "${CACHE_DIR:?}"/* 2>/dev/null || true
        debug "Cache cleared"
    fi
}

###########################################
# Profile Management Functions
###########################################

# Get current AWS profile with account information
ag_current() {
    _ag_check_dependencies || return 1
    
    if [ -z "$AWS_PROFILE" ]; then
        echo -e "${YELLOW}No AWS profile currently set${NC}"
        echo -e "${BLUE}Tip: Use 'ag_switch <profile>' to set a profile${NC}"
        return 1
    else
        echo -e "${GREEN}Current AWS profile: $AWS_PROFILE${NC}"
        
        # Try to get cached account info first
        local cache_key="${AWS_PROFILE}_identity"
        local cached_info
        
        # Check for --refresh flag
        if [ "$1" = "--refresh" ] || [ "$1" = "-r" ]; then
            _ag_clear_cache
            debug "Cache refresh requested"
        else
            cached_info=$(_ag_get_cache "$cache_key")
            if [ -n "$cached_info" ]; then
                echo "$cached_info"
                debug "Using cached account info"
                return 0
            fi
        fi
        
        # Fetch fresh account info with timeout
        debug "Fetching account information from AWS STS"
        local account_info
        account_info=$(_ag_run_with_timeout "${AWS_TIMEOUT}" aws sts get-caller-identity --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$account_info" ]; then
            local account_id=$(echo "$account_info" | jq -r '.Account // "Unknown"')
            local user_arn=$(echo "$account_info" | jq -r '.Arn // "Unknown"')
            local user_id=$(echo "$account_info" | jq -r '.UserId // "Unknown"')
            
            local output="${GREEN}Account ID: $account_id${NC}\n${GREEN}User ARN: $user_arn${NC}\n${GREEN}User ID: $user_id${NC}"
            echo -e "$output"
            
            # Cache the result
            _ag_set_cache "$cache_key" "$output"
        else
            echo -e "${RED}Unable to retrieve account information${NC}"
            echo -e "${YELLOW}Your credentials may have expired. Try: ag_login${NC}"
            return 1
        fi
    fi
}

# Alias for ag_current (more intuitive)
ag_whoami() {
    ag_current "$@"
}

# List available AWS profiles
ag_list() {
    _ag_check_dependencies || return 1
    
    echo -e "${GREEN}Available AWS profiles:${NC}"
    local profiles
    profiles=$(aws configure list-profiles 2>/dev/null | sort)
    
    if [ -z "$profiles" ]; then
        echo -e "${YELLOW}No profiles configured${NC}"
        echo -e "${BLUE}Tip: Configure profiles using 'aws configure --profile <name>'${NC}"
        return 1
    fi
    
    echo "$profiles" | while read -r profile; do
        if [ "$profile" = "$AWS_PROFILE" ]; then
            echo -e "  ${GREEN}* $profile${NC} (current)"
        else
            echo "    $profile"
        fi
    done
}

# Switch AWS profile with validation
ag_switch() {
    _ag_check_dependencies || return 1
    
    if [ -z "$1" ]; then
        echo -e "${RED}Error: Please provide a profile name${NC}"
        echo -e "${BLUE}Usage: ag_switch <profile-name>${NC}"
        echo ""
        ag_list
        return 1
    fi

    local profile="$1"
    
    # Validate profile exists
    if ! _ag_validate_profile "$profile"; then
        echo -e "${RED}Error: Profile '$profile' not found${NC}"
        echo ""
        ag_list
        return 1
    fi
    
    # Clear cache when switching profiles
    _ag_clear_cache
    
    export AWS_PROFILE="$profile"
    echo -e "${GREEN}Switched to profile: $profile${NC}"
    echo ""
    ag_current
}

# Login to AWS SSO with better error handling
ag_login() {
    _ag_check_dependencies || return 1
    
    local profile=${1:-$AWS_PROFILE}
    
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified or currently set${NC}"
        echo -e "${BLUE}Usage: ag_login [profile-name]${NC}"
        echo ""
        ag_list
        return 1
    fi
    
    # Validate profile exists
    if ! _ag_validate_profile "$profile"; then
        echo -e "${RED}Error: Profile '$profile' not found${NC}"
        echo ""
        ag_list
        return 1
    fi
    
    echo -e "${BLUE}Logging in to AWS SSO for profile: $profile${NC}"
    
    if _ag_run_with_timeout "${AWS_TIMEOUT}" aws sso login --profile "$profile" 2>&1; then
        # Clear cache after successful login
        _ag_clear_cache
        echo -e "${GREEN}Successfully logged in to profile: $profile${NC}"
        
        # Set profile if not already set
        if [ "$AWS_PROFILE" != "$profile" ]; then
            export AWS_PROFILE="$profile"
            echo -e "${GREEN}Profile set to: $profile${NC}"
        fi
    else
        echo -e "${RED}Failed to login to profile: $profile${NC}"
        return 1
    fi
}

# Logout from AWS SSO
ag_logout() {
    _ag_check_dependencies || return 1
    
    local profile=${1:-$AWS_PROFILE}
    
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified or currently set${NC}"
        echo -e "${BLUE}Usage: ag_logout [profile-name]${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Logging out from AWS SSO for profile: $profile${NC}"
    
    if _ag_run_with_timeout "${AWS_TIMEOUT}" aws sso logout --profile "$profile" 2>&1; then
        _ag_clear_cache
        echo -e "${GREEN}Successfully logged out from profile: $profile${NC}"
    else
        echo -e "${RED}Failed to logout from profile: $profile${NC}"
        return 1
    fi
}

# Validate current credentials
ag_validate() {
    _ag_check_dependencies || return 1
    
    local profile=${1:-$AWS_PROFILE}
    
    if [ -z "$profile" ]; then
        echo -e "${RED}Error: No profile specified or currently set${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Validating credentials for profile: $profile${NC}"
    
    local result
    result=$(AWS_PROFILE="$profile" _ag_run_with_timeout "${AWS_TIMEOUT}" aws sts get-caller-identity 2>&1)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Credentials are valid${NC}"
        return 0
    else
        echo -e "${RED}✗ Credentials are invalid or expired${NC}"
        echo -e "${YELLOW}Try running: ag_login $profile${NC}"
        return 1
    fi
}

###########################################
# Output Formatting Functions
###########################################

# Convert JSON to table format, handling nested structures
# Supports both piped input and command execution
ag_table() {
    _ag_check_dependencies || return 1
    
    local input
    if [ -p /dev/stdin ]; then
        # Read from pipe
        input=$(cat -)
    else
        # Execute command and capture output
        input=$(eval "$@" 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error executing command${NC}" >&2
            return 1
        fi
    fi
    
    if [ -z "$input" ]; then
        echo -e "${YELLOW}No data to display${NC}"
        return 0
    fi

    # JQ expression to flatten nested objects and convert to table format
    # 1. Flatten nested objects recursively
    # 2. Handle both object and array inputs
    # 3. Extract common AWS API response wrappers (repositories, Functions, StackSummaries)
    # 4. Format as TSV and use column for alignment
    echo "$input" | jq -r '
        def flatten_object:
            . as $in
            | reduce keys[] as $key
                ({}; . + {($key): ($in[$key] | if type == "object" then flatten_object else . end)})
            | to_entries
            | map({key: .key, value: .value | tostring})
            | from_entries;

        if type == "object" then
            .repositories // .Functions // .StackSummaries // . | map(flatten_object)
        elif type == "array" then
            map(flatten_object)
        else
            [.]
        end
        | if length > 0 then
            (.[0] | keys_unsorted) as $headers |
            ($headers | @tsv),
            ($headers | map(length | "*" * .) | @tsv),
            (.[] | [.[$headers[]]] | map(. // "-") | @tsv)
        else
            "No data or invalid format"
        end
    ' 2>/dev/null | column -ts $'\t' || {
        echo -e "${RED}Error: Invalid JSON format${NC}" >&2
        return 1
    }
}

# Format JSON object as key-value pairs with color coding
# Best for single objects or detailed views
ag_kv() {
    _ag_check_dependencies || return 1
    
    local input
    if [ -p /dev/stdin ]; then
        # Read from pipe
        input=$(cat -)
    else
        # Execute command and capture output
        input=$(eval "$@" 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error executing command${NC}" >&2
            return 1
        fi
    fi
    
    if [ -z "$input" ]; then
        echo -e "${YELLOW}No data to display${NC}"
        return 0
    fi

    # JQ expression to convert object to key-value pairs
    # Handles nested objects/arrays by converting to JSON strings
    # Uses ANSI color codes for green keys
    echo "$input" | jq -r '
        if type == "object" then
            to_entries | 
            .[] | 
            "\u001b[32m\(.key)\u001b[0m: \(.value | if type == "object" or type == "array" then tojson else tostring end)"
        else
            "Not an object"
        end
    ' 2>/dev/null || {
        echo -e "${RED}Error: Invalid JSON format${NC}" >&2
        return 1
    }
}

# Display JSON in tree/pretty format with syntax highlighting
# Uses 'less' for pagination on large outputs
ag_tree() {
    _ag_check_dependencies || return 1
    
    local input
    if [ -p /dev/stdin ]; then
        # Read from pipe
        input=$(cat -)
    else
        # Execute command and capture output
        input=$(eval "$@" 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error executing command${NC}" >&2
            return 1
        fi
    fi
    
    if [ -z "$input" ]; then
        echo -e "${YELLOW}No data to display${NC}"
        return 0
    fi

    # Use jq's color output (-C) and pipe to less with raw control characters (-R)
    # -F: quit if output fits on one screen
    # -X: don't clear screen on exit
    echo "$input" | jq -C '.' 2>/dev/null | less -RFX || {
        echo -e "${RED}Error: Invalid JSON format${NC}" >&2
        return 1
    }
}

###########################################
# Help Documentation
###########################################

# Quick reference guide
ag_help() {
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  AWS Goodies - Profile Management & Formatting Utility${NC}"
    echo -e "${GREEN}  Version 2.1.0${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${BLUE}Profile Management Commands:${NC}"
    echo "  ag_current / ag_whoami     - Show current AWS profile and account info"
    echo "  ag_list                    - List all available AWS profiles"
    echo "  ag_switch <profile>        - Switch to a different AWS profile"
    echo "  ag_login [profile]         - Login to AWS SSO"
    echo "  ag_logout [profile]        - Logout from AWS SSO"
    echo "  ag_validate [profile]      - Validate current credentials"

    echo -e "\n${BLUE}Output Formatting Commands:${NC}"
    echo "  ag_table                   - Format JSON array output as table"
    echo "  ag_kv                      - Format JSON object as key-value pairs"
    echo "  ag_tree                    - Show JSON in tree structure with syntax highlighting"

    echo -e "\n${BLUE}Common Usage Examples:${NC}"
    echo "  1. List CodeCommit repositories (table):"
    echo "     aws codecommit list-repositories | ag_table"
    
    echo -e "\n  2. Get caller identity (key-value):"
    echo "     aws sts get-caller-identity | ag_kv"
    
    echo -e "\n  3. List Lambda functions (table):"
    echo "     aws lambda list-functions | ag_table"
    
    echo -e "\n  4. View repository details (tree):"
    echo "     aws codecommit get-repository --repository-name REPO_NAME | ag_tree"
    
    echo -e "\n  5. List open pull requests with details:"
    echo "     aws codecommit list-pull-requests --pull-request-status OPEN | ag_tree"
    
    echo -e "\n  6. List CloudFormation stacks (table):"
    echo "     aws cloudformation list-stacks | ag_table"

    echo -e "\n${YELLOW}Profile Naming Convention:${NC}"
    echo "  sh-<account>-<role>"
    echo "    account: code-base, cicd, service-b, api, data"
    echo "    role: dev (Developer), pu (PowerUser), do (DevOps-ReadOnly), pa (PullRequest-Approver)"
    echo -e "  Example: sh-code-base-pa"

    echo -e "\n${BLUE}Configuration:${NC}"
    echo "  AWS_TIMEOUT           - Timeout for AWS commands (default: 30s)"
    echo "  CACHE_TTL             - Cache duration (default: 300s / 5 minutes)"
    echo "  AWS_PROFILE_DEBUG     - Set to 'true' to enable debug output"
    
    echo -e "\n${BLUE}Cache Management:${NC}"
    echo "  ag_current --refresh  - Refresh cached account information"
    echo "  Cache location: ~/.aws-goodies-cache"
    
    echo -e "\n${BLUE}Backward Compatibility:${NC}"
    echo "  Old 'aws_*' and 'awsg_*' commands still work via aliases"
}

###########################################
# Backward Compatibility Wrappers
###########################################

# Create wrapper functions for old function names (deprecated but maintained for compatibility)
# Using functions instead of aliases ensures compatibility in all contexts (scripts, interactive shells, etc.)

# awsg_* wrappers (previous version)
awsg_current() { ag_current "$@"; }
awsg_whoami() { ag_whoami "$@"; }
awsg_list() { ag_list "$@"; }
awsg_switch() { ag_switch "$@"; }
awsg_login() { ag_login "$@"; }
awsg_logout() { ag_logout "$@"; }
awsg_validate() { ag_validate "$@"; }
awsg_table() { ag_table "$@"; }
awsg_kv() { ag_kv "$@"; }
awsg_tree() { ag_tree "$@"; }
awsg_help() { ag_help "$@"; }

# aws_* wrappers (original version)
aws_current() { ag_current "$@"; }
aws_whoami() { ag_whoami "$@"; }
aws_list() { ag_list "$@"; }
aws_switch() { ag_switch "$@"; }
aws_login() { ag_login "$@"; }
aws_logout() { ag_logout "$@"; }
aws_validate() { ag_validate "$@"; }
aws_table() { ag_table "$@"; }
aws_kv() { ag_kv "$@"; }
aws_tree() { ag_tree "$@"; }
aws_help() { ag_help "$@"; }

###########################################
# Command Completion
###########################################

# Function to get profiles for completion (avoids errors if AWS CLI not available)
_ag_complete_profiles() {
    if command -v aws >/dev/null 2>&1; then
        aws configure list-profiles 2>/dev/null || echo ""
    fi
}

# Add command completion for new function names
complete -W "$(_ag_complete_profiles)" ag_switch ag_login ag_logout ag_validate

# Add command completion for old function names (backward compatibility)
complete -W "$(_ag_complete_profiles)" awsg_switch awsg_login awsg_logout awsg_validate
complete -W "$(_ag_complete_profiles)" aws_switch aws_login aws_logout aws_validate

###########################################
# Initialization
###########################################

# Run dependency check on load (non-blocking, just warns)
if ! _ag_check_dependencies 2>/dev/null; then
    echo -e "${YELLOW}Warning: aws-goodies loaded but some dependencies are missing${NC}" >&2
fi

# Set debug mode (use 'export AWS_PROFILE_DEBUG=true' to enable)
if [ "$AWS_PROFILE_DEBUG" = "true" ]; then
    DEBUG=true
    debug "Debug mode enabled"
    debug "AWS_TIMEOUT set to ${AWS_TIMEOUT}s"
    debug "CACHE_TTL set to ${CACHE_TTL}s"
fi

# Display welcome message only if interactive shell
if [ -n "$PS1" ] && [ "$AWS_GOODIES_QUIET" != "true" ]; then
    echo -e "${GREEN}AWS Goodies v2.1.0 loaded${NC} - Type 'ag_help' for usage"
fi
