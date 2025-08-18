# Agent Guidelines

This document outlines standards and practices that all software development agents must follow.

## Responsibilities

- Read and follow the appropriate phase specification documents (e.g., SPECp1.md).
- Maintain test coverage for each deliverable.
- Keep `README.md` and usage instructions up-to-date.
- Use declarative configuration files and group them into logical files.
- Follow project structure and naming conventions.
- **Update Brewfile**: Maintain the project's `Brewfile` when developer dependencies change, adding new tools or removing obsolete ones. Keep packages sorted alphabetically and ensure all development tools are available via `brew bundle`.

## Reference Material

### Project Documentation

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
  - Use `kubeconform --strict` for Kubernetes manifest validation (preferred)
  - Use `kubectl --dry-run=client -o yaml` for Kubernetes manifests when cluster is available
  - Use `yamllint` for general YAML validation
  - Use `shellcheck` for shell script validation
  - Use `markdownlint` for markdown documentation validation
  - Use `checkmake` for Makefile validation
  - Use appropriate linters for each file type
  - Fix all linting errors before proceeding

### Configuration Management

- Use declarative configuration approaches where possible
- Keep configuration separate from code
- Use environment-specific configurations appropriately
- Document all configuration requirements and options

### Testing Requirements

- Implement unit tests for individual components
- Create integration tests for system interactions
- Perform end-to-end testing for complete workflows
- Validate all functionality before marking tasks complete

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

## Best Practices

### Project Management

- Break complex tasks into manageable, well-defined steps
- Maintain clear progress tracking and status reporting
- Document decisions and rationale for future reference
- Ensure deliverables meet specified acceptance criteria

### Task Management

**TODO.md Maintenance Procedures:**

- **Session Startup**: Check `TODO.md` at the start of each work session to understand current project state and priorities
- **Status Updates**: Update task status when starting or completing work using appropriate status indicators
- **Discovery Documentation**: Add newly discovered issues or requirements to TODO.md immediately as they are identified
- **Completion Tracking**: Maintain running summary of completed work with completion dates for project history
- **Regular Reviews**: Review and reprioritize tasks periodically based on changing requirements and blockers
- **Next Steps Maintenance**: Keep next steps section updated with immediate actionable items

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

### Collaboration

- Follow established version control practices
- Write clear commit messages and pull request descriptions
- Document any breaking changes or migration requirements
- Communicate effectively about progress and blockers

### Version Control

- Commit changes periodically at logical milestones
- Create atomic commits with single logical changes
- Write clear, descriptive commit messages following conventional format
- Group related changes together
- Avoid mixing unrelated changes in single commits
- Commit after completing major features or fixing significant issues

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
