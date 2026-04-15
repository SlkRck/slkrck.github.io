# Build Tools

This directory contains reusable helper scripts that support repository automation and documentation.

## Tools

- **DocTools.ps1**  
  Versioning and documentation helper functions.

- **Show-RepoTree.ps1**  
  Repo-aware directory tree visualization tool.

- **TreeTool.ps1**  
  Generic directory tree helper functions.

These tools are typically dot-sourced by build scripts or used interactively during development.
These scripts are not intended to be imported as modules; they are executed directly.