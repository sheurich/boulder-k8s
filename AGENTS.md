# Agent Guidelines

This document outlines standards and practices that all software development agents must follow.

## Responsibilities

- Read and follow the appropriate phase specification documents (e.g., `reference/SPECp1.md`).
- Maintain test coverage for each deliverable.
- Keep `README.md` and usage instructions up-to-date.
- Use declarative configuration files and group them into logical files.
- Follow project structure and naming conventions.

## Reference Material

### Project Documentation

- **Boulder Development Environment Guide (`reference/BOULDER.md`)**: A comprehensive technical reference for the upstream Boulder project, detailing its architecture, services, configuration, and testing environment. This guide is essential for understanding the foundational Boulder patterns that this Kubernetes implementation adapts.
- Technical reference guides for project setup, architecture, and deployment
- Complete source code repositories with build configurations and test suites
- Project wikis with design documents, implementation guides, and coding standards

### Available Resources

- Development environment with appropriate tools and runtimes installed
- Access to project repositories and integration test scripts
- MCP (Model Context Protocol) tools for enhanced capabilities e.g. context7, github and repomix servers

## Development Standards

### Code Quality

- Follow established coding standards and best practices
- Implement comprehensive error handling and logging
- Write clear, maintainable, and well-documented code
- Ensure proper test coverage for all functionality
- **MANDATORY: Lint all files upon creation or modification**
  - Use `make lint` to run all project linting checks
  - The [`lint` target](Makefile) runs validation for all file types including Kubernetes manifests, YAML, shell scripts, Markdown, and Dockerfiles
  - Fix all linting errors before proceeding

- **CRITICAL: Verify deployment status properly**
  - **ALWAYS use `make status`** to check actual deployment health - see [Make Targets](README.md#make-targets)
  - Pod status "Running" ≠ Service actually working - verify service functionality
  - Check service logs and health endpoints to confirm services are truly operational
  - Example: A database pod might be "Running" but have authentication failures preventing actual use

### Configuration Management

- Use declarative configuration approaches where possible
- Keep configuration separate from code
- Use environment-specific configurations appropriately
- Document all configuration requirements and options

### Testing Requirements

- **End-to-End Validation**: The primary goal of testing in this project is to ensure the end-to-end ACME (Automated Certificate Management Environment) protocol workflow is fully functional and compliant.
- **OCSP Exclusion**: All tests must exclude OCSP (Online Certificate Status Protocol) functionality, as it is deprecated in the core Boulder software and not included in this Kubernetes implementation.
- **Service Dependencies**: Tests must validate that the strict startup order and dependencies between Boulder’s microservices are correctly handled by the Kubernetes deployment (e.g., using init containers).
- **Multi-Perspective Validation**: Challenge validation tests should confirm that checks are performed from multiple network perspectives (MPIC), a key security feature of Boulder.
- **Real-World Scenarios**: Tests should simulate realistic certificate issuance and management workflows that users will perform.

## Naming & Structure

### Resource Naming

- Use consistent naming conventions throughout the project
- Follow kebab-case for file and resource names
- Use descriptive names that indicate purpose and function
- Maintain naming consistency across all project components

### File Organization

- Group related files logically in appropriate directories
- Use clear, descriptive filenames that indicate content
- Keep directory structure simple and maintainable
- Document file organization patterns in project README

### Documentation Structure

- Maintain clear separation between different types of documentation
- Use consistent formatting and style guidelines
- Ensure documentation is easily navigable and searchable
- Keep documentation up-to-date with code changes

## Maintenance Procedures

This section consolidates all maintenance responsibilities that agents must perform to keep the project healthy and well-organized.

### File Maintenance

#### Brewfile Management

- **Update Brewfile**: Maintain the project's [`Brewfile`](Brewfile) when developer dependencies change
- Add new tools or remove obsolete ones as project requirements evolve
- Keep packages sorted alphabetically for easy maintenance
- Ensure all development tools are available via `brew bundle`

#### Lint Target Management

- **Lint Target Maintenance**: Update the [`scripts/lint.sh`](scripts/lint.sh) script and [`Makefile`](Makefile) lint target when adding new document types or locations
- Ensure the [`make lint`](Makefile) target covers all file types in the project
- Test lint targets after modifications to ensure they work correctly

#### Documentation Management

- Keep [`README.md`](README.md) and usage instructions up-to-date with project changes
- Maintain consistency between documentation files
- Update cross-references when file locations or structures change

### Process Maintenance

#### PROMPT.md Management

- **Update at checkpoints**: The [`PROMPT.md`](PROMPT.md) file must be updated at every checkpoint or handoff to ensure the next agent has a clear starting point
- **When to update**:
  - At the end of each work session
  - After completing major tasks or deliverables
  - Before any agent handoff
  - When the project status changes significantly (e.g., a new blocker is identified)
- **What to update**:
  - Current task status and progress
  - Repository status, including the current branch and recent commits
  - The immediate next tasks for the incoming agent
  - Any new blockers, issues, or architectural decisions
  - Changes to the environment or setup procedures

#### TODO.md Management

- **Session Startup**: Check [`TODO.md`](TODO.md) at the start of each work session to understand current project state and priorities
- **Status Updates**: Update task status when starting or completing work using appropriate status indicators
- **Discovery Documentation**: Add newly discovered issues or requirements immediately as they are identified
- **Completion Tracking**: Maintain running summary of completed work with completion dates for project history
- **Regular Reviews**: Review and reprioritize tasks periodically based on changing requirements and blockers
- **Next Steps Maintenance**: Keep next steps section updated with immediate actionable items

### Quality Maintenance

#### Code Standards

- Follow established coding standards and best practices
- Ensure proper test coverage for all deliverables
- Run [`make lint`](Makefile:10) before proceeding with changes
- Fix all linting errors before committing code

#### Testing Standards

- Maintain comprehensive test coverage for each deliverable
- Validate that end-to-end ACME protocol workflow remains functional
- Ensure service dependencies and startup ordering work correctly
- Test realistic certificate issuance and management workflows

## Best Practices

### Project Management

- Break complex tasks into manageable, well-defined steps
- Maintain clear progress tracking and status reporting
- Document decisions and rationale for future reference
- Ensure deliverables meet specified acceptance criteria

### Task Management

**Status Indicators:**

- `✅` (done) - Task completed and validated
- `🔄` (in progress) - Currently being worked on
- `🔴` (critical/urgent) - High priority task blocking other work
- `⏸️` (blocked) - Waiting on dependencies or external decisions
- `📋` (pending) - Planned but not yet started

**Task Documentation Guidelines:**

- Use markdown checkboxes for actionable items
- Include dates for completed items to maintain project timeline
- Add context notes for complex tasks requiring additional explanation
- Link to relevant documentation or code when applicable
- Document blockers with sufficient context for resolution
- Organize tasks by logical categories and implementation phases

**Weekly Review Process:**

1. Update completion status for all finished tasks
2. Assess and document any new blockers or impediments
3. Reprioritize pending tasks based on current project needs
4. Update next steps with upcoming week's focus areas
5. Review project phase progress and timeline adherence

### Agent Autonomous Behavior

- Complete assigned tasks fully before yielding back to user
- Never stop at uncertainty - research reasonable approaches and continue
- Document assumptions and proceed rather than asking for confirmation  
- Only escalate for unrecoverable errors or architectural decisions
- Provide brief progress updates as you execute each deployment step

### Collaboration

- Follow established version control practices
- Write clear commit messages and pull request descriptions
- Document any breaking changes or migration requirements
- Communicate effectively about progress and blockers

### Version Control

#### Logical Commit Grouping

- **Commit Timing**: Commit after each major task completion or when reaching a stable checkpoint
- **Group Related Changes**: Combine logically related changes into single commits
- **Separate Unrelated Changes**: Never mix different types of changes (e.g., don't combine Kubernetes manifests with documentation updates)
- **Atomic Commits**: Each commit should represent a single logical change that maintains project functionality
- **Conventional Format**: Use conventional commit format: `type(scope): description`

#### Commit Types

- **feat**: New features or functionality
- **fix**: Bug fixes and corrections
- **docs**: Documentation changes only
- **refactor**: Code restructuring without functional changes
- **test**: Adding or modifying tests
- **chore**: Maintenance tasks, tooling, dependencies

#### Logical Grouping Examples

- **Documentation cleanup**: All documentation updates, deletions, and consolidations in one commit
- **Kubernetes manifest updates**: All K8s YAML changes grouped together
- **Script changes**: Shell scripts, automation, and tooling modifications together
- **Configuration updates**: Environment configs, settings files, and parameters together
- **Database changes**: Schema, migrations, and data-related modifications together

#### When to Commit

**CRITICAL:** Commits MUST be performed at logical checkpoints throughout
development - this is not optional and ensures work is preserved and
collaboration remains effective.

- **After completing each subtask** or deliverable
- **Before switching to a different type of work** (e.g., from documentation
  to code)
- **After resolving merge conflicts** to maintain clean history
- **When reaching a stable checkpoint** where the project builds and runs
- **Before taking breaks** to save progress at logical points
- **After fixing linting errors** to maintain code quality standards

#### Commit Message Guidelines

- Use present tense: "Add feature" not "Added feature"
- Keep first line under 50 characters
- Provide detailed description in body for complex changes
- Reference issue numbers when applicable
- Explain the "why" not just the "what" for non-obvious changes

#### Commit Checkpoint Reminders

**CRITICAL:** Commits are mandatory checkpoint activities that must be
performed after each logical chunk of work is completed. Delaying commits
creates significant risks and collaboration challenges.

**Why This Matters:**

- **Risk Mitigation**: Uncommitted work can be lost due to system failures,
  accidental deletions, or environment issues
- **Collaboration**: Uncommitted changes make it impossible for team members
  to see progress or collaborate effectively
- **Recovery**: Regular commits provide rollback points when issues arise
  during development
- **Accountability**: Commits create an audit trail of work completed and
  progress made

**Commit Checkpoint Checklist - Commit After:**

- [ ] Fixing any bug or resolving an issue
- [ ] Updating documentation (README, guides, specifications)
- [ ] Implementing a feature or component
- [ ] Refactoring code or improving structure
- [ ] Adding or modifying tests
- [ ] Updating configuration files or scripts
- [ ] Completing linting and validation fixes
- [ ] Reaching any stable, working state
- [ ] Before switching context to different work
- [ ] At the end of each work session

**Remember:** Each commit should represent a complete, logical unit of work
that leaves the project in a functional state. If you can describe what you
did in a clear commit message, it's time to commit.

## Project-Specific Exclusions

### OCSP Functionality Deprecation

**IMPORTANT**: OCSP functionality is deprecated in Boulder and slated for removal. This Boulder Kubernetes implementation specifically excludes all OCSP-related services and functionality.

#### Excluded Services and Components

The following Boulder services/components are **NOT** implemented in this Kubernetes deployment:

- **OCSP Responder** - Service that responds to OCSP status requests
- **OCSP Generator** - Service that generates OCSP responses
- **OCSP Updater** - Service that updates OCSP response data
- **Akamai Purger** - Service for purging OCSP responses from Akamai CDN
- All OCSP-related configuration options and functionality
- All OCSP-related database tables and operations

#### Rationale

1. **Deprecated Status**: OCSP functionality is officially deprecated in Boulder
2. **Removal Timeline**: OCSP services are slated for complete removal from Boulder
3. **Modern Alternatives**: Certificate Transparency (CT) logs provide superior transparency and monitoring
4. **Reduced Complexity**: Excluding OCSP simplifies the Kubernetes deployment and reduces operational overhead

#### Implementation Impact

- Kubernetes manifests will not include OCSP service deployments
- Configuration files will omit OCSP-related settings
- Database initialization scripts will exclude OCSP tables
- Integration tests will not validate OCSP functionality
- Monitoring and alerting will not include OCSP metrics

**Note**: This exclusion does not affect core ACME functionality or certificate issuance capabilities.
