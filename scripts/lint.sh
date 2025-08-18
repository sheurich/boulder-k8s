#!/usr/bin/env bash

# lint.sh - Comprehensive linting script for boulder-k8s project
# Runs linting tools on various file types

set -euo pipefail

# Check if a command exists
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: $cmd is not installed or not in PATH"
        echo "Please install $cmd before running this script"
        exit 1
    fi
}

# Run a linting tool and capture result
run_linter() {
    local description="$1"
    shift
    echo "Running $description..."
    
    if "$@"; then
        echo "PASS: $description"
        return 0
    else
        echo "FAIL: $description"
        return 1
    fi
}

main() {
    echo "Boulder K8s Linting Script"
    echo "=========================="
    
    # Check required tools
    echo "Checking required tools..."
    check_command "yamllint"
    check_command "kubeconform"
    check_command "shellcheck"
    check_command "markdownlint"
    check_command "checkmake"
    echo "All required tools are available"
    echo
    
    # Track overall result
    exit_code=0
    
    # Run yamllint on all YAML files (excluding vendor directory)
    yaml_files=$(find . -name "*.yaml" -o -name "*.yml" | grep -v "^./vendor/" || true)
    if [ -n "$yaml_files" ]; then
        # shellcheck disable=SC2086
        if ! run_linter "yamllint on YAML files" yamllint $yaml_files; then
            exit_code=1
        fi
    else
        echo "SKIP: No YAML files found"
    fi
    echo
    
    # Run kubeconform on k8s directory (ignore missing schemas for CRDs)
    if [ -d "k8s" ]; then
        if ! run_linter "kubeconform on Kubernetes manifests" kubeconform --ignore-missing-schemas k8s/; then
            exit_code=1
        fi
    else
        echo "SKIP: No k8s directory found"
    fi
    echo
    
    # Run shellcheck on shell scripts (excluding vendor directory)
    shell_files=$(find . -name "*.sh" | grep -v "^./vendor/" || true)
    if [ -n "$shell_files" ]; then
        # shellcheck disable=SC2086
        if ! run_linter "shellcheck on shell scripts" shellcheck $shell_files; then
            exit_code=1
        fi
    else
        echo "SKIP: No shell scripts found"
    fi
    echo
    
    # Run markdownlint on markdown files (TEMPORARILY DISABLED)
    echo "SKIP: markdownlint temporarily disabled"
    # md_files=$(find . -name "*.md" | grep -v "^./vendor/" || true)
    # if [ -n "$md_files" ]; then
    #     # shellcheck disable=SC2086
    #     if ! run_linter "markdownlint on markdown files" markdownlint $md_files; then
    #         exit_code=1
    #     fi
    # else
    #     echo "SKIP: No markdown files found"
    # fi
    echo
    
    # Run checkmake on Makefile
    if [ -f "Makefile" ]; then
        if ! run_linter "checkmake on Makefile" checkmake Makefile; then
            exit_code=1
        fi
    else
        echo "SKIP: No Makefile found"
    fi
    echo
    
    # Final result
    if [ $exit_code -eq 0 ]; then
        echo "SUCCESS: All linting checks passed"
    else
        echo "FAILURE: Some linting checks failed"
    fi
    
    exit $exit_code
}

main "$@"