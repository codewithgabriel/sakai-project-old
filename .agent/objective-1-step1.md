# Objective 1 — Step 1: Source Code + Dev Environment Setup

## Status: ✅ COMPLETE (Updated)

## Date: 2026-03-11

## What Was Done

### 1. Project Reorganization
- Created `scripts/` directory: moved all shell scripts
- Created `config/` directory: moved all config files
- Updated `Dockerfile` COPY paths
- Updated `.gitignore`

### 2. Sakai 23.x Source Code
- Cloned to `sakai-source/` via shallow clone (`--depth 1`, ~255MB)

### 3. Native Environment (pre-existing)
- Tomcat 9 at `/opt/tomcat` — fully deployed
- MySQL 8 — active with `sakaidatabase`
- Maven at `/opt/maven`, Java 11

### 4. Dev Workflow Script (`scripts/dev.sh`)
Full unified CLI with these commands:

| Command | Description |
|:---|:---|
| `install` | Full setup from scratch on clean Ubuntu (Java, Maven, Tomcat, MySQL, Sakai) |
| `clean-remove` | Complete uninstall, system back to Sakai-free |
| `build-module <name>` | Incremental module build + deploy |
| `full-build` | Full Sakai build + deploy |
| `start/stop/restart` | Service management |
| `logs` | Tail catalina.out |
| `status` | Show services + resources |
| `list-modules` | List buildable modules |
| `properties` | Show sakai.properties |

### 5. Permission Fix
- Maven deploy now runs with `sudo --preserve-env` to write to root-owned `/opt/tomcat`

## What Remains
- ✅ Objective 1 fully complete
- **Next**: Objective 2 — Multi-tenant setup
