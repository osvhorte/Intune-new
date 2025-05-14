#!/bin/bash
#########################################################################
# Script: MacOS Computer Naming Script
# Description: Sets computer name based on serial number with validation
# Created By: Øystein Svendsen
# Created Date: 2025-02-17
# Last Modified: 2025-03-20
# Version: 2.0
#########################################################################

set -e  # Exit on error
set -u  # Exit on undefined variables

# Default Configuration
CUSTOMER="Eika"
CLIENT_PREFIX="Mac"
MAX_NAME_LENGTH=15
LOG_FILE="/var/log/tie_computer_naming.log"
BACKUP_FILE="/var/log/tie_computer_name.backup"
DRY_RUN=false

# Check if running from Jamf and use parameters if available
if [ "$0" = "/usr/local/jamf/bin/jamf" ] || [ "$0" = "/usr/local/bin/jamf" ]; then
    # Using Jamf parameters
    if [ ! -z "$4" ]; then CLIENT_PREFIX="$4"; fi
    if [ ! -z "$5" ]; then CUSTOMER="$5"; fi
    if [ "$6" = "true" ]; then DRY_RUN=true; fi
else
    # Parse command line options when running manually
    # Function to display usage
    usage() {
        echo "Usage: $0 [-d] [-p PREFIX] [-c CUSTOMER]"
        echo "  -d: Dry run - show what would be done without making changes"
        echo "  -p: Set client prefix (default: SKE)"
        echo "  -c: Set customer name (default: Skatteetaten)"
        exit 1
    }

    # Parse command line options
    while getopts "dp:c:h" opt; do
        case ${opt} in
            d) DRY_RUN=true ;;
            p) CLIENT_PREFIX=$OPTARG ;;
            c) CUSTOMER=$OPTARG ;;
            h) usage ;;
            \?) usage ;;
        esac
    done
fi

# Function to log messages - simplified without colors
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} - ${message}" >> "${LOG_FILE}"
    echo "${message}"
}

# Function to display error and exit - simplified without colors
error_exit() {
    log_message "ERROR: $1"
    exit 1
}

# Function to validate computer name
validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9-]+$ ]]; then
        error_exit "Computer name contains invalid characters"
    fi
    if [ ${#name} -gt $MAX_NAME_LENGTH ]; then
        error_exit "Computer name exceeds maximum length of $MAX_NAME_LENGTH characters"
    fi
}

# Function to set system names with error checking - simplified without colors
set_name() {
    local type="$1"
    local value="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log_message "Would set $type to $value (dry run)"
        return 0
    fi
    
    if ! scutil --set "$type" "$value"; then
        error_exit "Failed to set $type to $value"
    fi
    log_message "Successfully set $type to $value"
}

# Check if running as root
if [ "$(id -u)" != "0" ]; then
    error_exit "This script must be run as root"
fi

# Create log directory if it doesn't exist
mkdir -p "$(dirname "${LOG_FILE}")"

# Get serial number with error checking - simplified without colors
log_message "Retrieving serial number..."
serial=$(ioreg -l | grep IOPlatformSerialNumber | sed -e 's/.*\"\(.*\)\"/\1/')

if [ -z "$serial" ]; then
    error_exit "Could not retrieve serial number"
fi
log_message "Retrieved serial number: $serial"

# Initialize computer name
compName=""

# Generate computer name based on serial number format
if [ ${#serial} == 12 ] && [[ ${serial} =~ ^C02 ]]; then
    # Old format C02XXXXXYYYY
    first5="${serial:3:5}"
    last4="${serial: -4}"
    compName="${CLIENT_PREFIX}-${first5}-${last4}"
else
    # Handle newer serial number formats
    maxlength=$((${#serial}+${#CLIENT_PREFIX}+1))
    if [ $maxlength -lt $MAX_NAME_LENGTH ]; then
        compName="${CLIENT_PREFIX}-${serial}"
    else
        # If too long, use truncated version
        available_length=$(($MAX_NAME_LENGTH-${#CLIENT_PREFIX}-1))
        truncated_serial="${serial:0:$available_length}"
        compName="${CLIENT_PREFIX}-${truncated_serial}"
    fi
fi

# Validate generated name
validate_name "$compName"
log_message "Generated computer name: $compName"

# Set all names with error checking
log_message "Setting computer names..."
set_name "HostName" "$compName"
set_name "ComputerName" "$compName"
set_name "LocalHostName" "$compName"

# Verify the changes if not in dry run mode
if [ "$DRY_RUN" = false ]; then
    log_message "Verifying changes..."
    current_hostname=$(scutil --get HostName)
    if [ "$current_hostname" != "$compName" ]; then
        error_exit "Verification failed - hostname does not match"
    fi
    
    log_message "Computer naming process completed successfully!"
fi

exit 0 