#!/usr/bin/env bash
# =============================================================================
# setup-github-repo.sh
#
# Run this script ONE TIME from inside the sigma-nu-60th folder to:
#   1. Initialize a local git repository
#   2. Commit the files
#   3. Create a PRIVATE GitHub repo called "Sigma-Nu-60th"
#   4. Push everything up
#
# Prerequisites:
#   • Git installed  (check: git --version)
#   • GitHub CLI installed  (check: gh --version)
#     Install: https://cli.github.com/
#   • Logged in to GitHub CLI  (run once: gh auth login)
#
# Usage:
#   cd sigma-nu-60th
#   chmod +x setup-github-repo.sh
#   ./setup-github-repo.sh
# =============================================================================

set -e   # stop immediately if any command fails

REPO_NAME="Sigma-Nu-60th"
DESCRIPTION="Google Apps Script automation to build the Sigma Nu 60th Anniversary registration form"

echo ""
echo "========================================"
echo "  Sigma Nu 60th — GitHub Repo Setup"
echo "========================================"
echo ""

# ── 1. Make sure we're in the right folder ───────────────────────────────────
if [ ! -f "createForm.gs" ]; then
  echo "❌  ERROR: createForm.gs not found."
  echo "    Please run this script from inside the sigma-nu-60th folder."
  exit 1
fi

# ── 2. Initialize local git repo ─────────────────────────────────────────────
echo "▶  Initializing local git repository..."
git init
git add .
git commit -m "Initial commit: Google Form builder for 60th Anniversary"
echo "✅  Local git repo initialized."
echo ""

# ── 3. Create the private GitHub repo and push ───────────────────────────────
echo "▶  Creating private GitHub repo: $REPO_NAME ..."
gh repo create "$REPO_NAME" \
  --private \
  --description "$DESCRIPTION" \
  --source=. \
  --remote=origin \
  --push

echo ""
echo "✅  Done! Your private repo is live."
echo ""
echo "    View it at: https://github.com/$(gh api user --jq .login)/$REPO_NAME"
echo ""
