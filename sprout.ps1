<#
.SYNOPSIS
  One command to start / stop the whole Sprout environment (Docker Desktop, Jenkins, SonarQube, the app).

.EXAMPLE
  .\sprout.cmd            # start everything and open the browser (same as "start")
  .\sprout.cmd stop       # stop Jenkins and the app (data is kept)
  .\sprout.cmd status     # show container status
#>
param(
  [ValidateSet('start', 'stop', 'status')]
  [string]$Action = 'start'
)

$ErrorActionPreference = 'Continue'  # docker writes progress to stderr; failures are checked via $LASTEXITCODE
Set-Location $PSScriptRoot

$jenkinsCompose = @('-f', 'ci/docker-compose.jenkins.yml', '--env-file', 'ci/.env')

function Read-CiConfiguration {
  # Use Compose's dotenv parser so quoted passwords and literal dollar signs work.
  # Capture the configuration; never print its credential values to the terminal.
  $configurationText = docker compose @jenkinsCompose config --format json
  if ($LASTEXITCODE -ne 0) { throw 'Invalid CI configuration; check ci/.env.' }
  $configuration = $configurationText | ConvertFrom-Json
  $jenkinsEnvironment = $configuration.services.jenkins.environment
  return @{
    JENKINS_PORT = $configuration.services.jenkins.ports[0].published
    JENKINS_ADMIN_ID = $jenkinsEnvironment.JENKINS_ADMIN_ID
    SPROUT_DB_PASSWORD = $jenkinsEnvironment.SPROUT_DB_PASSWORD
    SONAR_PORT = $jenkinsEnvironment.SONAR_PORT
  }
}

function Test-DockerEngine {
  docker info --format '{{.ServerVersion}}' *> $null
  return $LASTEXITCODE -eq 0
}

function Start-DockerEngine {
  if (Test-DockerEngine) { return }

  # docker.exe lives in <install>\resources\bin; Docker Desktop.exe in <install>
  $dockerExe = (Get-Command docker -ErrorAction SilentlyContinue).Source
  $candidates = @(
    $(if ($dockerExe) { Join-Path (Split-Path (Split-Path (Split-Path $dockerExe))) 'Docker Desktop.exe' }),
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  ) | Where-Object { $_ -and (Test-Path $_) }
  if (-not $candidates) { throw 'Docker Desktop not found. Start it manually and rerun.' }

  Write-Host '>> Starting Docker Desktop...' -ForegroundColor Cyan
  Start-Process $candidates[0] -WindowStyle Hidden
  for ($i = 0; $i -lt 90; $i++) {
    if (Test-DockerEngine) { Write-Host '   Docker engine is running.'; return }
    Start-Sleep 2
  }
  throw 'Docker engine did not start within 3 minutes.'
}

function Wait-Http($name, $url, $tries = 60, $mustContain = $null) {
  Write-Host "   Waiting for $name ($url)..." -NoNewline
  for ($i = 0; $i -lt $tries; $i++) {
    try {
      $res = Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 3
      if (-not $mustContain -or $res.Content -match [regex]::Escape($mustContain)) {
        Write-Host ' up' -ForegroundColor Green; return $true
      }
    } catch {
      # Jenkins answers 403 before login: that still means it's up
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 403) {
        Write-Host ' up' -ForegroundColor Green; return $true
      }
    }
    Start-Sleep 2
  }
  Write-Host ' timed out' -ForegroundColor Yellow; return $false
}

if (-not (Test-Path 'ci/.env')) {
  throw 'ci/.env is missing. Copy ci/.env.example to ci/.env and fill it in first.'
}
$ciEnv = Read-CiConfiguration
$jenkinsPort = if ($ciEnv.JENKINS_PORT) { $ciEnv.JENKINS_PORT } else { '8081' }
$sonarPort = if ($ciEnv.SONAR_PORT) { $ciEnv.SONAR_PORT } else { '9002' }
$appPort = if ($env:APP_PORT) { $env:APP_PORT } else { '8090' }

switch ($Action) {
  'start' {
    Start-DockerEngine

    Write-Host '>> Starting Jenkins + SonarQube...' -ForegroundColor Cyan
    docker compose @jenkinsCompose up -d --build
    if ($LASTEXITCODE -ne 0) { throw 'Failed to start Jenkins/SonarQube.' }

    Write-Host '>> Starting the app...' -ForegroundColor Cyan
    # Use the same DB password Jenkins deploys with, and keep the image version that was last deployed.
    if ($ciEnv.SPROUT_DB_PASSWORD) { $env:POSTGRES_PASSWORD = $ciEnv.SPROUT_DB_PASSWORD }
    $backendId = docker inspect --format '{{.Image}}' sprout-backend-1 2>$null
    $frontendId = docker inspect --format '{{.Image}}' sprout-frontend-1 2>$null
    $releaseBuild = docker inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' sprout-backend-1 2>$null
    if ($backendId -and $frontendId -and $releaseBuild -and $releaseBuild -ne '<no value>') {
      $env:BACKEND_IMAGE = $backendId
      $env:FRONTEND_IMAGE = $frontendId
      $env:IMAGE_TAG = $releaseBuild
      Write-Host "   Using deployed build: $releaseBuild"
      # Start an already deployed release without rerunning schema migrations or replacing its configuration.
      docker compose start db backend frontend
    } else {
      if ($backendId) {
        Write-Host '   Backing up the legacy database before the migration transition.'
        docker compose start db
        if ($LASTEXITCODE -ne 0) { throw 'Could not start the legacy database for backup.' }
        for ($i = 0; $i -lt 30; $i++) {
          docker compose exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' *> $null
          if ($LASTEXITCODE -eq 0) { break }
          Start-Sleep 2
        }
        $legacyBackupName = "legacy-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')).dump"
        New-Item -ItemType Directory -Force '.backups' | Out-Null
        docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -f "$1" && pg_restore --list "$1" >/dev/null' sh "/tmp/$legacyBackupName"
        if ($LASTEXITCODE -ne 0) { throw 'Legacy database backup failed; leaving the old release intact.' }
        $databaseId = docker compose ps -q db
        docker cp "${databaseId}:/tmp/$legacyBackupName" (Join-Path '.backups' $legacyBackupName)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot copy the legacy backup; leaving the old release intact.' }
        docker compose exec -T db rm -f "/tmp/$legacyBackupName"
        Write-Host "   Verified backup: .backups/$legacyBackupName"
      }
      Write-Host '   No managed release found; building images locally and applying checked schema migrations.'
      docker compose up -d --build --wait --wait-timeout 180
    }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to start the app.' }

    $jenkinsUp = Wait-Http 'Jenkins' "http://localhost:$jenkinsPort/login"
    $appUp = Wait-Http 'Sprout' "http://localhost:$appPort/api/health"
    # SonarQube needs 1-2 minutes to boot
    $sonarUp = Wait-Http 'SonarQube' "http://localhost:$sonarPort/api/system/status" 90 '"status":"UP"'

    if ($jenkinsUp) { Start-Process "http://localhost:$jenkinsPort/job/sprout/" }
    if ($appUp) { Start-Process "http://localhost:$appPort" }
    if ($sonarUp) { Start-Process "http://localhost:$sonarPort/dashboard?id=sprout" }

    Write-Host ''
    Write-Host "Jenkins : http://localhost:$jenkinsPort  (user: $($ciEnv.JENKINS_ADMIN_ID), password in ci/.env)" -ForegroundColor Green
    Write-Host "App     : http://localhost:$appPort" -ForegroundColor Green
    Write-Host "API docs: http://localhost:$appPort/api/docs" -ForegroundColor Green
    Write-Host "SonarQube: http://localhost:$sonarPort  (configure the analysis token and webhook as described in docs/DEPLOYMENT.md)" -ForegroundColor Green
  }

  'stop' {
    if (-not (Test-DockerEngine)) { Write-Host 'Docker is not running; nothing to stop.'; return }
    Write-Host '>> Stopping the app...' -ForegroundColor Cyan
    docker compose stop
    Write-Host '>> Stopping Jenkins + SonarQube...' -ForegroundColor Cyan
    docker compose @jenkinsCompose stop
    Write-Host 'Stopped. Data (database, Jenkins jobs/history) is kept.' -ForegroundColor Green
  }

  'status' {
    if (-not (Test-DockerEngine)) { Write-Host 'Docker is not running.'; return }
    docker ps -a --filter 'name=sprout' --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
  }
}
