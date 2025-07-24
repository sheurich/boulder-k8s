# AI Agent Developer Guidelines

This document provides guidelines for AI software development agents contributing to this project.

## 1. Overview

This repository is managed by human operators supervising AI agents. The end-to-end process for operators is documented in `docs/agent-workflow.md`. As an agent, your role is to follow the instructions in a given task, adhere to the guidelines below, and produce code and documentation changes.

## 2. Core Principles

- **Understand the Goal**: Before writing any code, ensure you understand the requirements from the task description. If anything is ambiguous, ask for clarification.
- **Follow Instructions**: Adhere strictly to the instructions given in the task. Do not perform work outside the scope of the request.
- **Use Best Practices**: Always use software development best practices for the languages and tools involved.
- **Respect Existing Code**: Follow the existing conventions, style, and architecture of the project.

## 3. Workflow

1.  **Receive Task**: A task will be assigned to you, usually via a GitHub issue.
2.  **Analyze and Plan**:
    -   Read the task description carefully.
    -   Identify the files that need to be changed. If you need to edit files not provided in the context, ask for them by their full path.
    -   Formulate a step-by-step plan to implement the required changes.
3.  **Propose Changes**:
    -   Propose changes using the specified `SEARCH/REPLACE` block format.
    -   Keep changes small and focused. One logical change per commit.
    -   Provide a clear explanation for your changes.
4.  **Suggest Commands**: If applicable, suggest shell commands to run tests, install dependencies, or view changes.

## 4. Code Contribution

- **Code Style**: Follow established style guides for the relevant languages (e.g., PEP 8 for Python, `shfmt` for shell scripts).
- **Documentation**: Update documentation (e.g., `docs/architecture.md`, READMEs) when you make changes to the system's behavior or architecture.
- **Testing**: When adding new features or fixing bugs, add or update tests to cover the changes.
- **Commit Hygiene**: All changes must be submitted with clear, descriptive commit messages. Commits should be atomic, representing a single logical change. The repository's history is an audit artifact.

## 5. Communication

- **Clarity**: Be clear and concise in your communication.
- **Asking Questions**: If a requirement is unclear, ask specific questions to resolve the ambiguity.
- **Reporting Progress**: Provide updates on your progress as requested.
