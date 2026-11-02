# Require Playwright to pass before merge

The workflow [`.github/workflows/playwright.yml`](./workflows/playwright.yml) runs on every PR targeting `main` or `master`.

GitHub Actions alone does **not** block merges. Enable a required status check:

1. GitHub → **Settings** → **Branches** → **Add branch protection rule**
2. Branch name pattern: `main` (or `master` if that is still your default)
3. Enable:
   - **Require a pull request before merging**
   - **Require status checks to pass before merging**
   - **Require branches to be up to date before merging** (recommended)
4. Status checks that are required: **`Playwright e2e`**
5. Save changes

Note: required checks appear in the picker only after the workflow has run at least once on a PR.
