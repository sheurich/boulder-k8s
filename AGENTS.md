# **Agent & Contributor Onboarding Guide**

This document provides a clear, machine-readable workflow for any agent (human or AI) joining the Boulder Kubernetes Migration project. Following this process ensures that work is efficient, context is maintained, and handoffs are seamless.

## **Onboarding Workflow**

To get started, follow these two steps in order:

### **Step 1: Understand the Goal (The "What" and "Why")**

- **Action:** Read the **PRD.md** (Product Requirements Document) in its entirety.
- **Purpose:** This document contains the high-level project goals, scope, and the specific requirements for each phase of the migration. It is the single source of truth for what a "complete" and "correct" implementation looks like. Do not start work without understanding these objectives.

### **Step 2: Understand the Current State (The "Where We Are")**

- **Action:** Read the **PROGRESS.md** file, starting from the oldest entry and reading to the newest.
- **Purpose:** This document is a chronological log of all work performed on the project. It tells you what has been accomplished, what challenges were faced, and what key decisions were made.
- **CRITICAL:** Pay close attention to the most recent entry. It will detail:
  - The last completed tasks.
  - The current primary blocker or problem.
  - The immediate next steps recommended by the previous agent.

## **How to Contribute**

Once you have completed the onboarding workflow, you are ready to begin work.

1. **Identify Your Task:** Based on the latest entry in PROGRESS.md, identify the immediate priority. The "Problems or blockers" and "Next Tasks" sections will guide you.
2. **Execute Your Task:** Perform the development work required to address the priority task.
3. **Document Your Work:** Before finishing your session, you **must** update the PROGRESS.md file.
   - Add a new entry with the current date (YYYY-MM-DD).
   - Summarize what you accomplished.
   - State what is currently in progress.
   - Detail any new problems or blockers you encountered and how you recommend solving them.
   - Leave clear notes and advice for the next agent who will pick up where you left off.

This cycle of **Read \-\> Execute \-\> Document** is essential for the project's success.
