# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in mattpocock/skills | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## Lifecycle labels (local only)

These two labels are not part of the mattpocock/skills triage vocabulary above — they track implementation progress once an issue moves past triage.

| Label              | Meaning                                                          |
| ------------------ | ----------------------------------------------------------------- |
| `agent-is-working` | An agent has started implementing this issue                     |
| `done`             | Implementation is complete and committed                          |

An agent sets `Status: agent-is-working` when it begins work on an issue, and `Status: done` when it commits the implementation. See `docs/agents/issue-tracker.md` for the full lifecycle.
