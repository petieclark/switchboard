# Switchboard Worker Protocol

Every agent worker follows this exact loop when fired by its cron:

## 1. Check Queue
```bash
bash ~/clawd/skills/agentboard/scripts/task-queue.sh <agent_name>
```

If `count == 0`: stop immediately. Nothing to do.

## 2. Take the First Task
The queue is already priority-sorted. Take `queue[0]`.

Note the task `id`, `title`, `description`, `context`, and `tags`.

## 3. Claim It (Atomic)
```bash
bash ~/clawd/skills/agentboard/scripts/task-claim.sh <agent_name> <task_id>
```

If you get a 409: another agent grabbed it. Re-check the queue and take the next one, or stop.

## 4. Execute
Use the `context` field as your primary instructions. The `description` is the summary; `context` is the detail.

Do the actual work using all available tools.

## 5. Write Output
```bash
bash ~/clawd/skills/agentboard/scripts/task-output.sh <task_id> <done|failed|review> "<summary of what was done>"
```

- `done`: task completed successfully
- `failed`: hit a blocker, explain why in output
- `review`: work done but needs human verification before closing

## 6. Send Completion Message
```bash
bash ~/clawd/skills/agentboard/scripts/msg-send.sh <agent_name> "Task #<id> complete: <one-liner>" friday <task_id>
```

## Hard Rules
- Never claim more than one task per worker run
- If context is empty and the task is ambiguous, mark failed with "insufficient context"
- If the task requires human action or approval, mark review with explanation
- Always write output even if the task failed — explain what happened
