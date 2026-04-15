# Infrastructure Automation Repository

This repository contains reusable automation, tooling, and reference implementations for infrastructure, cloud, and systems management workflows.

The structure is intentionally segmented by domain to support clarity, reuse, and automation at scale.


## Table of contents

- [WinMgmt](./WinMgmt/)
  - [SNIPS](./WinMgmt/SNIPS/)
    - [modules](./WinMgmt/SNIPS/modules/)
    - [functions](./WinMgmt/SNIPS/functions/)
  - [SCRIPTS](./WinMgmt/SCRIPTS/)

- [Azure](./Azure/)
  - [SNIPS](./Azure/SNIPS/)
    - [modules](./Azure/SNIPS/modules/)
    - [functions](./Azure/SNIPS/functions/)

- [Terraform](./Terraform/)
  - [Modules](./Terraform/Modules/)
    - [Examples](./Terraform/Modules/Examples/)

## Repository Structure

- **Azure/**  
  Azure-specific scripts, snippets, and Pester tests.

- **Terraform/**  
  Terraform modules and usage examples.

- **WinMgmt/**  
  Windows management scripts, modules, and supporting tooling.

- **build/**  
  Repository-level build, test, documentation, and helper tools.

- **tests/**  
  Repository-wide test enforcement (style, header compliance, etc.).

## Conventions

- Keep reusable code in SNIPS/.
- Put publishable PowerShell modules under SNIPS/modules/.
- Put single-purpose helper functions under SNIPS/functions/.
- Put runnable scripts in SCRIPTS/.
- Terraform modules live under Terraform/Modules/.

## Intended Use

This repository is designed to:
- Serve as a working automation toolbox
- Act as a reference implementation for scripting standards
- Support CI-style validation through Pester
- Enable selective reuse of scripts, modules, and snippets

Each top-level directory contains its own README with domain-specific guidance.