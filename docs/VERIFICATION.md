# Deployment validation record

Validated on 2026-10-15 using Docker Desktop's Linux engine. All application and
database checks used disposable `sprout-hardening-*` projects. The existing app,
its database, the mentor's portal and its stored credentials were not deployed
to or reconfigured.

| Check | Result |
|---|---|
| Backend pytest against PostgreSQL 16 | 20 passed; app statement/branch coverage 98.29%; 80% minimum enforced |
| Frontend Vitest inside the Node 24 test image | 14 passed; 97.77% statements, 96.96% branches, 94.11% functions, 100% lines |
| Release-image end-to-end tests through nginx/API/PostgreSQL | 7 passed |
| Backend, frontend, e2e and Jenkins Docker builds | Passed with pinned base images and verified dependency installs |
| Application and self-test Jenkinsfiles | Accepted by the Jenkins Declarative Pipeline validator |
| Jenkins Configuration as Code | Checked and started in an isolated controller with test credentials and no deployment jobs |
| Python dependency audit | `pip-audit --strict`: no known vulnerabilities found |
| Frontend dependency audit | `npm audit`: zero vulnerabilities after the tooling upgrade |
| Runtime image gates | Trivy: no fixable HIGH/CRITICAL findings in either app image |
| Source secret scan | Passed on the tracked/new source snapshot, excluding ignored environment files |
| Software bills of materials | CycloneDX generated for backend and frontend images |
| Runtime configuration | Both app containers use read-only root filesystems; password values absent from app/database container environment configuration |
| PostgreSQL recovery drill | Custom-format archive restored to an empty database; row count and schema revision verified; populated target refused |
| Failed release recovery | Deliberately changed both images and removed the frontend JS bundle; smoke failed, both original image IDs were restored, recovered build passed smoke |
| Failed rollback / first-release recovery | Isolated shell regression checks preserve the pending marker on rollback failure, block another release, allow explicit recovery, and preserve the database after a failed first release |
| Schema safety | Fresh upgrade/downgrade, model consistency, legacy data preservation, incompatible legacy schema/PK rejection, and SQL rendering covered by tests |
| Shell/PowerShell and Compose configuration | Parsed successfully; local, test, production and integration combinations validated |

The image gate explicitly ignores vulnerabilities with no available fix. The
record reflects the advisory databases available on this date; CI reruns the
checks for each release. See the Jenkinsfile for exact commands and thresholds.

The authenticated SonarQube analysis/webhook Quality Gate and Docker Hub publication
still require the deployment environment's portal setup and credentials. Their
pipeline definitions and required IDs were checked, but this validation did not
publish images or change the real SonarQube server. HTTPS, ingress authentication,
branch protection, off-host backup retention and monitoring are environment tasks
listed in [DEPLOYMENT.md](DEPLOYMENT.md).

The workflow follows the supplied `../cicd-portal` reference. The webhook behavior
uses the official [Jenkins SonarQube integration](https://www.jenkins.io/doc/pipeline/steps/sonar/),
and production overrides follow [Docker's Compose production guidance](https://docs.docker.com/compose/how-tos/production/).
