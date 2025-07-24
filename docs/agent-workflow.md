# Agent Workflow

This document describes the process for using an AI agent to accomplish development tasks within this repository.

## Overview

The core workflow is based on GitHub Issues. Each task for an agent is defined in an issue. The human operator's role is to create well-defined issues, provide the agent with necessary context (like file contents), apply the agent's proposed changes, and verify the results.

## Step-by-Step Process

1.  **Identify or Create a Task**
    -   Review the high-level tasks in `TASKS.md`.
    -   Choose an uncompleted task to work on.

2.  **Create a GitHub Issue**
    -   Create a new GitHub issue using the "Task" template (`.github/ISSUE_TEMPLATE/task.md`).
    -   Fill out the template with a clear description, acceptance criteria, and any relevant technical details. A well-defined task is crucial for agent success.

3.  **Engage the Agent**
    -   Start your AI agent.
    -   Provide the agent with the content of the GitHub issue as its initial prompt.
    -   Also provide the `AGENT_GUIDELINES.md` to ensure it understands the rules of engagement for this repository.

4.  **Supervise the Agent**
    -   The agent will analyze the task and may ask for the contents of specific files. Provide these files as requested.
    -   The agent will propose changes using `SEARCH/REPLACE` blocks. Carefully review these changes.
    -   Apply the proposed changes to your local files.

5.  **Test and Verify**
    -   After applying changes, run any relevant tests to ensure the changes work as expected and haven't introduced regressions.
    -   Verify that all acceptance criteria from the task issue have been met.
    -   If the task is not complete or there are issues, continue the dialogue with the agent, providing feedback and test results.

6.  **Commit the Changes**
    -   Once the task is complete and verified, commit the changes to git.
    -   Follow the commit hygiene guidelines: use a clear, descriptive commit message that references the task (e.g., `feat(ra): Implement new registration flow (closes #123)`).

7.  **Close the Issue**
    -   Close the corresponding GitHub issue.
