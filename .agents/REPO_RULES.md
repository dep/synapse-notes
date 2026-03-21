### Important Repo Rules:

- DO NOT commit trailing whitespace. Please clean this up.
- DO NOT "undo" or "reset" changes you noticed that you didn't make -- these were made by another person and you should assume they were correct.

<critical_workflow>
**MANDATORY BUILD & RELAUNCH**

### macOS Build and Relaunch
Whenever you modify `.swift` files, you MUST rebuild and relaunch the app BEFORE you ask the user for feedback or perform git operations.

Use `@.agents/commands/RELOAD.md on macOS`

Do not skip this step, even if unit tests pass. This overrides the "Minimize Verification Loops" rule.

### Mobile Build and Relaunch

Whenever you modify `mobile/` files, you MUST rebuild and relaunch the app BEFORE you ask the user for feedback or perform git operations.

Do not skip this step, even if unit tests pass. This overrides the "Minimize Verification Loops" rule.

Use `@.agents/commands/RELOAD.md on android`

"🚀 **Rebuilt and relaunched the Synapse app.**"
</critical_workflow>
