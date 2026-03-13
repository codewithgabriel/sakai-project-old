# Sakai 23.x Development Environment Setup

## Objective 1: Sakai Source Code + Dev Server ✅ COMPLETE
Per prompt rule #1, tackling one objective at a time.

- [x] **1.1** Clone Sakai 23.x source code into the project directory
- [x] **1.2** Reorganize project structure (scripts → `scripts/`, configs → `config/`)
- [x] **1.3** Set up development workflow — [scripts/dev.sh](file:///home/gabriel/Documents/sakai-project-dev/scripts/dev.sh) created
- [x] **1.4** Configure Sakai to run **natively** (Tomcat + MySQL — already deployed from previous install)
- [x] **1.5** Verify the dev server starts and Sakai portal loads (service is active)
- [x] **1.6** Add [install](file:///home/gabriel/Documents/sakai-project-dev/scripts/dev.sh#177-369) command — full automated setup from clean Ubuntu
- [x] **1.7** Add `clean-remove` command — complete uninstall, system back to clean

## Objective 2: Multi-Tenant Setup ✅ COMPLETE
- [x] Fix nginx configs with proper proxy headers
- [x] Update `sakai.properties` to accept subdomain requests
- [x] Configure single Sakai instance for multiple universities
- [x] Subdomain-based tenant routing via nginx
- [x] Admin site at main.aflon.com.ng

## Objective 3: Per-Tenant Theming ✅ COMPLETE
- [x] Different color themes per university subdomain

## Objective 4: Faculty/Department/Course Hierarchy (IN PROGRESS)
- [ ] Research Sakai Hierarchy API / Service
- [ ] Define data structure for Faculty -> Department -> Level -> Course
- [ ] Create skeleton for the "Faculties" tool (custom tool or customized existing tool)
- [ ] Implement drill-down navigation UI
- [ ] Integrate with Content Hosting (Resources) for lecture materials (PDFs)

## Objective 5: Custom Landing Pages (FUTURE)
- [ ] Hide Sakai branding, show custom welcome pages per subdomain

## Checkpoint Notes
- **Environment**: Java 11 ✅, Maven 3.8.7 ✅, Tomcat 9 ✅, MySQL active ✅
- **Sakai Service**: Active and enabled (systemd) ✅
- **Disk**: ~14GB free
- **RAM**: ~2GB available
- **Hosts**: [/etc/hosts](file:///etc/hosts) configured for aflon subdomains ✅
- **Nginx**: Not yet configured for aflon subdomains
