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

function Read-EnvFile($path) {
  $vars = @{}
  if (Test-Path $path) {
    foreach ($line in Get-Content $path) {
      if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { $vars[$Matches[1]] = $Matches[2].Trim() }
    }
  }
  return $vars
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
  Start-Process $candidates[0]
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
$ciEnv = Read-EnvFile 'ci/.env'
$jenkinsPort = if ($ciEnv.JENKINS_PORT) { $ciEnv.JENKINS_PORT } else { '8081' }
$sonarPort = if ($ciEnv.SONAR_PORT) { $ciEnv.SONAR_PORT } else { '9002' }
$appPort = if ($env:APP_PORT) { $env:APP_PORT } else { '8090' }

switch ($Action) {
  'start' {
    Start-DockerEngine

    Write-Host '>> Starting Jenkins + SonarQube...' -ForegroundColor Cyan
    docker compose @jenkinsCompose up -d
    if ($LASTEXITCODE -ne 0) { throw 'Failed to start Jenkins/SonarQube.' }

    Write-Host '>> Starting the app...' -ForegroundColor Cyan
    # Use the same DB password Jenkins deploys with, and keep the image version that was last deployed.
    if ($ciEnv.SPROUT_DB_PASSWORD) { $env:POSTGRES_PASSWORD = $ciEnv.SPROUT_DB_PASSWORD }
    # Deployed image looks like <namespace>/sprout-backend:<build>
    $deployed = docker inspect --format '{{.Config.Image}}' sprout-backend-1 2>$null
    if ($LASTEXITCODE -eq 0 -and $deployed -match '^(.+)/sprout-backend:(.+)$') {
      $env:IMAGE_NAMESPACE = $Matches[1]
      $env:IMAGE_TAG = $Matches[2]
      Write-Host "   Using deployed build: $deployed"
      docker compose up -d --no-build
    } else {
      Write-Host '   No deployed build found; building images locally (Jenkins will replace them on its next build).'
      docker compose up -d --build
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
    Write-Host "SonarQube: http://localhost:$sonarPort  (user: admin, SONAR_ADMIN_PASSWORD in ci/.env; set by the first pipeline run)" -ForegroundColor Green
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
