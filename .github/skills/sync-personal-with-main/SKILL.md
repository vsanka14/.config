---
name: sync-personal-with-main
description: Update this repository's personal branch from the latest main branch while preserving intentional personal-only differences. Use when asked to sync, merge, or update personal from main.
---

# Sync `personal` with `main`

Update `personal` by merging the latest `main`; do not rebase or rewrite either
branch.

1. Confirm the repository root, current branch, remotes, and worktree state.
   Never discard, overwrite, or silently stash uncommitted changes. If the
   worktree is dirty and those changes prevent a safe sync, ask before
   proceeding.
2. Fetch `origin`.
3. Record the prior shared baseline before merging:

   ```bash
   base=$(git merge-base personal origin/main)
   git diff "$base"..personal
   ```

   Treat this diff as the source of truth for intentional `personal` overrides.
   Content merely present on `personal` but unchanged from the baseline is
   stale `main` content, not a personal customization.
4. Fast-forward local `main` only:

   ```bash
   git switch main
   git pull --ff-only origin main
   ```

5. Switch to `personal` and merge `main`:

   ```bash
   git switch personal
   git merge main
   ```

6. Resolve conflicts with a three-way comparison among the recorded baseline,
   pre-merge `personal`, and updated `main`. Keep new behavior and structural
   improvements from `main`, then reapply the intentional changes shown in the
   baseline-to-`personal` diff. Never resolve every conflict wholesale with
   `--ours` or `--theirs`.
7. In this repository, known intentional `personal` overrides currently
   include a three-workspace setup and its matching Aerospace/SketchyBar
   mappings, plus compact personal-machine gaps. Preserve those overrides while
   retaining unrelated `main` improvements such as event architecture, shell
   compatibility, status items, and display profiles.
8. Check for conflict markers, validate changed shell/config files using the
   repository's existing checks, and inspect the final diff from `main` to
   ensure the personal-only delta remains intentional.
9. Commit the merge when conflicts required manual resolution, then push
   `personal` to `origin`. Do not push `main`.
