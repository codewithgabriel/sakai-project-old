# Faculty/Department/Course Hierarchy Tool — Implementation Plan

## Background

Objective 4 requires a **Faculties** tool in Sakai that admin can add to any project site. When users navigate to it, they see a drill-down hierarchy:

**Faculties → Departments → Levels (100–500) → Courses → Lecture Materials (PDFs)**

Admin must be able to **configure per-site** which faculties/departments are visible.

### What Already Exists

| File | Status |
|:---|:---|
| [hierarchy.json](file:///home/gabriel/Documents/sakai-project-dev/config/hierarchy.json) | ✅ 15 faculties + departments, but **no levels or courses** |
| [sakai.faculties.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/WEB-INF/tools/sakai.faculties.xml) | ⚠️ Uses `<tools>` tag instead of `<registration>` |
| [faculties.vm](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/vm/faculties/faculties.vm) | ⚠️ Basic template, needs admin/config views |
| [web.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/WEB-INF/web.xml) | ⚠️ References `FacultiesServlet` that doesn't exist |
| [pom.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/pom.xml) | ⚠️ Still has chat-tool dependencies |
| Java source files | ❌ **None exist** |

## User Review Required

> [!IMPORTANT]
> **Data structure decision**: The current [hierarchy.json](file:///home/gabriel/Documents/sakai-project-dev/config/hierarchy.json) has faculties and departments but **no levels or courses**. I plan to extend it with a `levels` array (100–500) per department, each containing a `courses` array. Each course will have a `code`, `title`, and `materials` array (for linking to lecture PDFs in Content Hosting). Should I pre-populate with sample courses, or leave them empty for admin to configure?

> [!IMPORTANT]
> **Admin configuration approach**: I'll store per-site configuration using Sakai's **tool properties** (`ToolConfiguration.getPlacementConfig()`). Admin can select which faculties and departments to show. This is the standard Sakai way to store tool-specific settings per site placement. Is this acceptable, or would you prefer a database-backed approach?

> [!WARNING]
> **Content Hosting integration**: Lecture materials (PDFs) will be stored in Sakai's Resources (Content Hosting Service). At the course level, the tool will look for resources under a conventional path like `/content/group/{siteId}/faculties/{faculty}/{dept}/{level}/{courseCode}/`. Admin will upload lecture PDFs to these folders using the standard Resources tool, and the Faculties tool will read and display them.

---

## Proposed Changes

### Component 1: Cleanup & Fix pom.xml

#### [MODIFY] [pom.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/pom.xml)

- Remove all chat-specific dependencies (`sakai-chat-api`, `sakai-mergedlist-util`, JSF2, tomahawk, etc.)
- Add proper dependencies: `sakai-kernel-api`, `sakai-kernel-util`, `sakai-component-manager`, `velocity`, `commons-lang3`, `jackson-databind` (for JSON parsing), `servlet-api`
- Keep parent pointing to the hierarchy base module

---

### Component 2: Fix Tool Registration

#### [MODIFY] [sakai.faculties.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/WEB-INF/tools/sakai.faculties.xml)

- Change root tag from `<tools>` to `<registration>` (Sakai standard)
- Keep `id="sakai.faculties"`, title, description, and category course/project

---

### Component 3: Java Backend — FacultiesServlet

#### [NEW] [FacultiesServlet.java](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/java/org/sakaiproject/hierarchy/tool/FacultiesServlet.java)

A Velocity-based servlet extending `VelocityPortletPaneledAction` (Sakai's standard pattern for Velocity tools). Responsibilities:
- Read the hierarchy data from [hierarchy.json](file:///home/gabriel/Documents/sakai-project-dev/config/hierarchy.json) (loaded from classpath or config path)
- Handle navigation state via request parameters (`view=faculties|departments|levels|courses|materials`, `facultyId`, `deptId`, `level`)
- Build breadcrumbs for navigation context
- Render the appropriate Velocity template

#### [NEW] [FacultiesAdminServlet.java](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/java/org/sakaiproject/hierarchy/tool/FacultiesAdminServlet.java)

Admin configuration handler:
- Read/save per-site configuration (selected faculties, departments) using Sakai ToolConfiguration placement properties
- Provide a configuration form with checkboxes for faculties and their departments
- Check `SiteService.allowUpdateSite()` for admin permission gating

#### [NEW] [HierarchyDataService.java](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/java/org/sakaiproject/hierarchy/tool/HierarchyDataService.java)

Service class to:
- Parse [hierarchy.json](file:///home/gabriel/Documents/sakai-project-dev/config/hierarchy.json) and cache in memory
- Provide methods: `getFaculties()`, `getDepartments(facultyAcronym)`, `getLevels()`, `getCourses(deptAcronym, level)`
- Filter results based on site-level config (which faculties/depts are enabled)
- Integrate with `ContentHostingService` to list course materials (PDFs)

#### [NEW] [HierarchyData.java](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/java/org/sakaiproject/hierarchy/tool/model/HierarchyData.java)

POJO models:
- `Faculty` (name, acronym, departments[])
- `Department` (name, acronym)
- `Course` (code, title)
- `LectureMaterial` (name, url, size, lastModified)

---

### Component 4: Velocity Templates (Views)

#### [MODIFY] [faculties.vm](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/vm/faculties/faculties.vm)

Rewrite to use Sakai's standard portlet CSS and the `#parse` includes. Add proper breadcrumb navigation and responsiveness.

#### [NEW] departments.vm, levels.vm, courses.vm, materials.vm

One template per level of the hierarchy:
- **departments.vm** — lists departments under selected faculty
- **levels.vm** — shows levels 100–500 for selected department
- **courses.vm** — lists courses for selected level
- **materials.vm** — lists lecture PDFs with download links

#### [NEW] admin.vm

Admin configuration page:
- Checkbox tree: Faculty → Department selection
- Save/cancel buttons
- Permission-gated (only shown to site maintainers)

---

### Component 5: web.xml Fixes

#### [MODIFY] [web.xml](file:///home/gabriel/Documents/sakai-project-dev/sakai-source/hierarchy/hierarchy-tool/src/webapp/WEB-INF/web.xml)

- Add `sakai.request` filter (required by all Sakai tools)
- Wire `FacultiesServlet` properly with Sakai's Velocity pattern
- Add listener for `ToolListener`

---

### Component 6: Extend hierarchy.json

#### [MODIFY] [hierarchy.json](file:///home/gabriel/Documents/sakai-project-dev/config/hierarchy.json)

Add `levels` and `courses` structure:
```json
{
  "departments": [
    {
      "name": "Computer Science",
      "acronym": "CSC",
      "levels": [
        {
          "level": 100,
          "courses": [
            {"code": "CSC101", "title": "Introduction to Computer Science"},
            {"code": "CSC102", "title": "Introduction to Programming"}
          ]
        }
      ]
    }
  ]
}
```

---

## Verification Plan

### Manual Verification (by you, the user)

Since this is a Sakai tool that renders inside the portal UI, testing requires running the Sakai server:

1. **Build the module**: `scripts/dev.sh build-module hierarchy`
2. **Restart Sakai**: `scripts/dev.sh restart`
3. **Add tool to a site**:
   - Log in as admin
   - Go to a project site → Site Info → Edit Tools
   - Find "Faculties" in the tool list and add it
4. **Test drill-down navigation**:
   - Click Faculties → see list of faculties
   - Click a faculty → see its departments
   - Click a department → see levels (100–500)
   - Click a level → see courses
   - Click a course → see materials (if any uploaded)
5. **Test admin config**:
   - As site maintainer, click the settings/config icon in the tool
   - Select/deselect faculties and departments
   - Save → verify only selected items appear in the navigation
6. **Test permission gating**: Log in as a regular student user and verify the config option is hidden

> [!NOTE]
> I'll verify the Maven build succeeds (`mvn clean install`) before asking you to restart Sakai. If there are compilation errors, I'll fix them before proceeding.
