#!/bin/bash
# Centralized logging infrastructure for snapshot scripts
#
# This module provides logging functions that output to both console and log file.
# All log entries are timestamped and categorized by level.

# Log file path (set by setup_logging)
LOG_FILE=""
DEBUG_MODE="${DEBUG_MODE:-false}"

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize logging system
# Usage: setup_logging <output_dir>
setup_logging() {
    local output_dir="$1"
    
    if [ -z "${output_dir}" ]; then
        echo "Error: Output directory required for logging setup" >&2
        return 1
    fi
    
    # Create output directory if it doesn't exist
    mkdir -p "${output_dir}"
    
    # Set log file path
    LOG_FILE="${output_dir}/snapshot.log"
    
    # Initialize log file with header
    {
        echo "=========================================="
        echo "Snapshot Log - $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "=========================================="
        echo ""
    } > "${LOG_FILE}"
    
    log_info "Logging initialized: ${LOG_FILE}"
}

# Get timestamp for log entries
_get_timestamp() {
    date -u +"%Y-%m-%d %H:%M:%S UTC"
}

# Write to both console and log file
_write_log() {
    local level="$1"
    local message="$2"
    local color="$3"
    local timestamp=$(_get_timestamp)
    
    # Format log entry
    local log_entry="[${timestamp}] [${level}] ${message}"
    local console_entry="${color}[${level}]${NC} ${message}"
    
    # Write to console (with color if terminal)
    if [ -t 1 ]; then
        echo -e "${console_entry}"
    else
        echo "${log_entry}"
    fi
    
    # Write to log file (without color)
    if [ -n "${LOG_FILE}" ]; then
        echo "${log_entry}" >> "${LOG_FILE}"
    fi
}

# Log info message
# Usage: log_info "message"
log_info() {
    _write_log "INFO" "$1" "${BLUE}"
}

# Log warning message
# Usage: log_warn "message"
log_warn() {
    _write_log "WARN" "$1" "${YELLOW}"
}

# Log error message
# Usage: log_error "message"
log_error() {
    _write_log "ERROR" "$1" "${RED}"
}

# Log debug message (only if DEBUG_MODE is enabled)
# Usage: log_debug "message"
log_debug() {
    if [ "${DEBUG_MODE}" = "true" ] || [ "${DEBUG_MODE}" = "1" ]; then
        _write_log "DEBUG" "$1" "${NC}"
    fi
}

# Log step progress
# Usage: log_step <step_number> <step_name>
log_step() {
    local step_number="$1"
    local step_name="$2"
    local message="Step ${step_number}: ${step_name}"
    
    log_info ""
    log_info "=========================================="
    log_info "${message}"
    log_info "=========================================="
    log_info ""
}

# Log success message
# Usage: log_success "message"
log_success() {
    _write_log "SUCCESS" "$1" "${GREEN}"
}

# Log section header
# Usage: log_section "section name"
log_section() {
    log_info ""
    log_info "--- $1 ---"
}

# Log command execution
# Usage: log_command "command description" "command"
log_command() {
    local description="$1"
    local command="$2"
    
    log_debug "Executing: ${description}"
    log_debug "Command: ${command}"
}

# Log file operation
# Usage: log_file_op "operation" "file_path"
log_file_op() {
    local operation="$1"
    local file_path="$2"
    
    log_debug "File ${operation}: ${file_path}"
}

# Get log file path
# Usage: get_log_file
get_log_file() {
    echo "${LOG_FILE}"
}

# Check if logging is initialized
# Usage: is_logging_initialized
is_logging_initialized() {
    [ -n "${LOG_FILE}" ] && [ -f "${LOG_FILE}" ]
}
