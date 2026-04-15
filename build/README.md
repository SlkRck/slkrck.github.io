# Build and Repository Tooling

This directory contains repository-level automation used to support building, testing, documentation, and validation.

## Contents

- **Build.ps1**  
  Primary build orchestration script.

- **Invoke-RepoPester.ps1**  
  Executes repository-wide Pester tests.

- **Insert-ReadmeHeader.ps1**  
  Enforces standardized README and script headers.

- **tools/**  
  Shared helper scripts used by build and documentation workflows.

These scripts are not intended to be imported as modules; they are executed directly.
