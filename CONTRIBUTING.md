# Contributing and release review

Use a short-lived branch and a pull request for each change. Protect `main` in the
Git hosting settings: require an independent review and a successful Jenkins run,
block force pushes, and dismiss approvals after code changes. Repository files
cannot enforce those remote settings. Only trusted contributors may change or run
the deployment job: access to the host Docker socket grants control of the host.
Run untrusted pull requests on a separate agent without production credentials or
the deployment Docker socket.

Before merging:

- Run backend and frontend tests; include regression coverage for changed behavior.
- For schema changes, commit an Alembic revision and review the generated SQL.
  Use expand/contract changes: add compatible schema first, deploy compatible code,
  backfill, and remove old schema in a later release after the rollback window.
- Regenerate dependency locks after editing `.in` files or `package.json`, review
  the diff, and pass vulnerability checks. Never suppress an advisory without a
  documented owner, reason and expiry.
- Require a green SonarQube Quality Gate. Configure new-code coverage >= 80%,
  duplication <= 3%, no new reliability/security issues, and review all new security
  hotspots. Set the new-code baseline explicitly in SonarQube; the scanner cannot
  create these server-side policies.
- Test the release images through the full Compose stack. Deployment must use the
  exact tested images, with no rebuild and no mutable `latest` promotion.
- Review the backup/rollback impact and update [the runbook](docs/DEPLOYMENT.md).

For each release retain the Git revision, both image IDs/registry digests, test
reports and CycloneDX SBOMs. Keep current and previous images locally until rollback
has been exercised; configure registry retention to preserve supported releases.
Schedule a restore drill and an off-host backup copy, rather than relying only on
successful dump commands.
