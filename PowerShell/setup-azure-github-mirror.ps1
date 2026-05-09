# =============================================================================
# setup-azure-github-mirror.ps1
#
# Automates the full setup of Azure DevOps as primary git repo with GitHub
# as a downstream mirror, synced via Azure Pipelines on every push.
#
# Prerequisites:
#   - Azure CLI   : https://learn.microsoft.com/en-us/cli/azure/install-azure-cli
#   - git         : https://git-scm.com/downloads
#   - Run from inside your local git repository directory
#
# Usage (if execution policy blocks scripts, run this first):
#   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#
# Then run:
#   .\setup-azure-github-mirror.ps1
# =============================================================================

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers -----------------------------------------------------------------

function Write-Info    { param($msg) Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "  OK $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "  !! $msg" -ForegroundColor Yellow }
function Write-Header  {
    param($msg)
    Write-Host ""
    Write-Host "  $msg" -ForegroundColor White
    Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
}
function Abort { param($msg) Write-Host "  ERROR: $msg" -ForegroundColor Red; exit 1 }

# =============================================================================
# 1. Prerequisites
# =============================================================================
function Check-Prerequisites {
    Write-Header "Checking prerequisites"

    # Must be inside a git repo
    $null = git rev-parse --is-inside-work-tree 2>&1
    if ($LASTEXITCODE -ne 0) { Abort "Not inside a git repository. cd into your project folder first, or run this script from anywhere inside the repo." }

    # Always run from the repo root so .azure-pipelines/ is created in the right place
    $repoRoot = git rev-parse --show-toplevel
    if ($PWD.Path -ne (Resolve-Path $repoRoot).Path) {
        Write-Info "Navigating to repo root: $repoRoot"
        Set-Location $repoRoot
    }
    Write-Success "Working from repo root: $repoRoot"

    # az CLI
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Abort "Azure CLI not found.`n  Install: https://aka.ms/installazurecliwindows"
    }
    Write-Success "Azure CLI is available."

    # git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Abort "git not found.`n  Install: https://git-scm.com/downloads"
    }
    Write-Success "git is available."

    # azure-devops extension
    $ext = az extension show --name azure-devops 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Installing azure-devops CLI extension..."
        az extension add --name azure-devops --only-show-errors
        Write-Success "azure-devops extension installed."
    } else {
        Write-Success "azure-devops CLI extension is installed."
    }
}

# =============================================================================
# 2. Collect inputs
# =============================================================================
function Collect-Inputs {
    Write-Header "Configuration"
    Write-Host ""

    Write-Host "  Azure DevOps" -ForegroundColor White
    $script:ADO_ORG     = Read-Host "    Organization name "
    $script:ADO_PROJECT = Read-Host "    Project name      "
    $script:ADO_REPO    = Read-Host "    Repository name   "

    Write-Host ""
    Write-Host "  GitHub" -ForegroundColor White
    $script:GH_USER = Read-Host "    Username          "
    $script:GH_REPO = Read-Host "    Repository name   "

    Write-Host ""
    Write-Host "  Branch" -ForegroundColor White
    $branchInput = Read-Host "    Branch name [main]"
    $script:BRANCH = if ($branchInput -eq '') { 'main' } else { $branchInput }

    $script:ADO_ORG_URL  = "https://dev.azure.com/$($script:ADO_ORG)"
    $script:ADO_REPO_URL = "$($script:ADO_ORG_URL)/$($script:ADO_PROJECT)/_git/$($script:ADO_REPO)"
    $script:GH_REPO_URL  = "https://github.com/$($script:GH_USER)/$($script:GH_REPO).git"

    Write-Host ""
    Write-Host "  Will configure:"
    Write-Host "    Source (Azure DevOps) : $($script:ADO_REPO_URL)"
    Write-Host "    Mirror (GitHub)       : https://github.com/$($script:GH_USER)/$($script:GH_REPO)"
    Write-Host "    Sync branch           : $($script:BRANCH)"
    Write-Host ""

    $confirm = Read-Host "  Proceed? [Y/n]"
    if ($confirm -ne '' -and $confirm -notmatch '^[Yy]$') {
        Write-Info "Aborted."
        exit 0
    }
}

# =============================================================================
# 3. GitHub PAT (only manual step)
# =============================================================================
function Get-GitHubPAT {
    Write-Header "GitHub Personal Access Token"

    $patUrl = "https://github.com/settings/tokens/new?scopes=repo&description=azure-devops-sync"

    Write-Info "Opening GitHub token creation page in your browser..."
    Write-Info "The 'repo' scope will be pre-selected."
    Write-Host ""

    Start-Process $patUrl

    Write-Host "  Steps in the browser:"
    Write-Host "    1. Confirm 'repo' scope is checked"
    Write-Host "    2. Set expiration as desired (90 days recommended)"
    Write-Host "    3. Click 'Generate token'"
    Write-Host "    4. Copy the token"
    Write-Host ""

    # Read-Host -AsSecureString hides the input, then convert back to plain text
    $securePat = Read-Host "  Paste your GitHub PAT (input hidden)" -AsSecureString
    $script:GITHUB_PAT = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePat)
    )

    if ([string]::IsNullOrWhiteSpace($script:GITHUB_PAT)) { Abort "No PAT provided." }

    if ($script:GITHUB_PAT -notmatch '^gh') {
        Write-Warn "Token doesn't look like a standard GitHub PAT (expected prefix: ghp_ or github_pat_)."
        Write-Warn "Continuing — the pipeline run will confirm whether it's valid."
    }

    Write-Success "PAT received."
}

# =============================================================================
# 4. Azure login
# =============================================================================
function Invoke-AzureLogin {
    Write-Header "Azure authentication"

    $account = az account show --query "user.name" -o tsv 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Already logged in as: $account"
    } else {
        Write-Info "Not logged in — starting Azure login..."
        az login --only-show-errors
        Write-Success "Azure login successful."
    }

    az devops configure --defaults `
        organization=$($script:ADO_ORG_URL) `
        project=$($script:ADO_PROJECT) 2>$null

    Write-Success "Azure DevOps defaults set: org=$($script:ADO_ORG), project=$($script:ADO_PROJECT)"
}

# =============================================================================
# 5. Variable Group
# =============================================================================
function Create-VariableGroup {
    Write-Header "Azure DevOps Variable Group"

    $existingId = az pipelines variable-group list `
        --query "[?name=='github-sync-secrets'].id" `
        -o tsv 2>$null

    if (-not [string]::IsNullOrWhiteSpace($existingId)) {
        Write-Warn "Variable group 'github-sync-secrets' already exists (id: $existingId)."
        Write-Info "Updating GITHUB_PAT value..."
        az pipelines variable-group variable update `
            --group-id $existingId `
            --name "GITHUB_PAT" `
            --value $script:GITHUB_PAT `
            --secret true `
            --only-show-errors | Out-Null
        $script:VAR_GROUP_ID = $existingId
        Write-Success "Variable group updated."
    } else {
        Write-Info "Creating variable group 'github-sync-secrets'..."
        $script:VAR_GROUP_ID = az pipelines variable-group create `
            --name "github-sync-secrets" `
            --variables "GITHUB_PAT=$($script:GITHUB_PAT)" `
            --authorize true `
            --query "id" `
            --only-show-errors `
            -o tsv

        az pipelines variable-group variable update `
            --group-id $script:VAR_GROUP_ID `
            --name "GITHUB_PAT" `
            --secret true `
            --only-show-errors | Out-Null

        Write-Success "Variable group created (id: $($script:VAR_GROUP_ID)). GITHUB_PAT marked as secret."
    }
}

# =============================================================================
# 6. Local git remotes
# =============================================================================
function Setup-GitRemotes {
    Write-Header "Local git remotes"

    $currentOrigin = git remote get-url origin 2>$null

    if ([string]::IsNullOrWhiteSpace($currentOrigin)) {
        Write-Info "No origin set — adding Azure DevOps as origin..."
        git remote add origin $script:ADO_REPO_URL

    } elseif ($currentOrigin -match 'github\.com') {
        Write-Info "Current origin is GitHub — renaming to 'github', adding Azure DevOps as origin..."
        git remote rename origin github
        git remote add origin $script:ADO_REPO_URL

    } elseif ($currentOrigin -match 'dev\.azure\.com') {
        Write-Info "Origin already points to Azure DevOps."
        $hasGithub = git remote get-url github 2>$null
        if ([string]::IsNullOrWhiteSpace($hasGithub)) {
            Write-Info "Adding 'github' remote for reference..."
            git remote add github $script:GH_REPO_URL
        }

    } else {
        Write-Warn "Origin points to an unrecognised URL: $currentOrigin"
        Write-Info "Adding Azure DevOps as a remote named 'azure'..."
        git remote add azure $script:ADO_REPO_URL
    }

    Write-Host ""
    Write-Success "Remotes:"
    git remote -v | ForEach-Object { Write-Host "    $_" }
}

# =============================================================================
# 7. Pipeline YAML
# =============================================================================
function Create-PipelineYaml {
    Write-Header "Pipeline YAML"

    $yamlDir  = ".azure-pipelines"
    $yamlFile = "$yamlDir\sync-to-github.yml"

    if (-not (Test-Path $yamlDir)) { New-Item -ItemType Directory -Path $yamlDir | Out-Null }

    # Note: $(GITHUB_PAT) is an Azure Pipelines variable reference, not PowerShell —
    # using a here-string with single quotes prevents PowerShell from expanding it.
    $yamlContent = @"
trigger:
  branches:
    include:
      - $($script:BRANCH)

pool:
  vmImage: 'ubuntu-latest'

variables:
  - group: github-sync-secrets

steps:
  - checkout: self
    fetchDepth: 0
    persistCredentials: true

  - script: |
      git config user.email "azure-sync@noreply.com"
      git config user.name "Azure DevOps Sync"
      git remote add github \
        https://`$(GITHUB_PAT)@github.com/$($script:GH_USER)/$($script:GH_REPO).git
      git push github HEAD:$($script:BRANCH) --force-with-lease
    displayName: 'Mirror to GitHub'
"@

    Set-Content -Path $yamlFile -Value $yamlContent -Encoding UTF8
    Write-Success "Pipeline YAML written to $yamlFile"
}

# =============================================================================
# 8. Commit and push
# =============================================================================
function Commit-AndPush {
    Write-Header "Committing pipeline file"

    git add ".azure-pipelines\sync-to-github.yml"

    # Check if there is anything staged
    $staged = git diff --cached --name-only
    if ([string]::IsNullOrWhiteSpace($staged)) {
        Write-Warn "Pipeline file already committed — nothing to commit."
    } else {
        git commit -m "ci: add GitHub mirror sync pipeline [skip ci]"
        Write-Success "Committed pipeline file."
    }

    Write-Info "Pushing to Azure DevOps (origin $($script:BRANCH))..."
    git push origin $script:BRANCH
    Write-Success "Pushed to Azure DevOps."
}

# =============================================================================
# 9. Register the pipeline
# =============================================================================
function Register-Pipeline {
    Write-Header "Registering pipeline"

    $existingPipeline = az pipelines list `
        --query "[?name=='Mirror to GitHub'].id" `
        -o tsv 2>$null

    if (-not [string]::IsNullOrWhiteSpace($existingPipeline)) {
        Write-Warn "Pipeline 'Mirror to GitHub' already exists (id: $existingPipeline). Skipping creation."
        $script:PIPELINE_ID = $existingPipeline
    } else {
        Write-Info "Creating pipeline 'Mirror to GitHub'..."
        $script:PIPELINE_ID = az pipelines create `
            --name "Mirror to GitHub" `
            --repository $script:ADO_REPO `
            --repository-type tfsgit `
            --branch $script:BRANCH `
            --yml-path ".azure-pipelines/sync-to-github.yml" `
            --skip-first-run true `
            --only-show-errors `
            --query "id" -o tsv
        Write-Success "Pipeline created (id: $($script:PIPELINE_ID))."
    }
}

# =============================================================================
# 10. Run and verify
# =============================================================================
function Run-AndVerify {
    Write-Header "Running pipeline — first sync to GitHub"

    $runId = az pipelines run `
        --name "Mirror to GitHub" `
        --branch $script:BRANCH `
        --only-show-errors `
        --query "id" -o tsv

    Write-Info "Pipeline run started (run id: $runId). Polling for result..."
    Write-Host "  " -NoNewline

    $maxAttempts = 36  # ~6 minutes
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        $status = az pipelines runs show --id $runId --query "status" -o tsv 2>$null
        $result = az pipelines runs show --id $runId --query "result" -o tsv 2>$null

        if ($status -eq 'completed') {
            Write-Host ""
            if ($result -eq 'succeeded') {
                Write-Success "Pipeline run succeeded. GitHub is now in sync."
            } else {
                Write-Host ""
                Abort "Pipeline run finished with result: $result`n`n  Check the logs at:`n  $($script:ADO_ORG_URL)/$($script:ADO_PROJECT)/_build/results?buildId=$runId`n`n  Common causes:`n  - GitHub PAT lacks 'repo' scope -> regenerate and update the Variable Group`n  - GitHub username or repo name typo -> re-run this script`n  - GitHub repo does not exist yet -> create it first (can be empty)"
            }
            return
        }

        Write-Host "." -NoNewline
        Start-Sleep -Seconds 10
    }

    Write-Host ""
    Write-Warn "Timed out waiting for pipeline to complete."
    Write-Info "Check status at: $($script:ADO_ORG_URL)/$($script:ADO_PROJECT)/_build/results?buildId=$runId"
}

# =============================================================================
# 11. Summary
# =============================================================================
function Print-Summary {
    Write-Host ""
    Write-Host "  $('═' * 52)" -ForegroundColor Green
    Write-Host "  Setup complete!" -ForegroundColor Green
    Write-Host "  $('═' * 52)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Source of truth  : $($script:ADO_REPO_URL)"
    Write-Host "  GitHub mirror    : https://github.com/$($script:GH_USER)/$($script:GH_REPO)"
    Write-Host "  Sync pipeline    : Mirror to GitHub  (triggers on push to $($script:BRANCH))"
    Write-Host ""
    Write-Host "  Your workflow from now on:"
    Write-Host ""
    Write-Host "    git add / git commit"
    Write-Host "    git push origin $($script:BRANCH)    <- GitHub updates automatically"
    Write-Host ""
    Write-Host "  Use Azure DevOps for: Boards, PRs, Work Items, Pipelines"
    Write-Host "  Use GitHub for:       Portfolio, open-source visibility, backup"
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================
Write-Host ""
Write-Host "  Azure DevOps -> GitHub Mirror Setup" -ForegroundColor White
Write-Host "  $('═' * 50)" -ForegroundColor DarkGray

Check-Prerequisites
Collect-Inputs
Get-GitHubPAT
Invoke-AzureLogin
Create-VariableGroup
Setup-GitRemotes
Create-PipelineYaml
Commit-AndPush
Register-Pipeline
Run-AndVerify
Print-Summary