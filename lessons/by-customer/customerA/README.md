# Customer A Lessons

Placeholder for lessons captured from Customer A projects (when they onboard).

## Expected Structure

When Customer A bootstraps their first project, lessons will be captured as:
- `customerA-L-001.md`, `customerA-L-002.md`, etc.

Each lesson will be tagged with:
- `origin_project: customerA-[project-type]`
- `customer_affected: [strategix, customerA]` (if the lesson applies to Strategix too)
- `universal: true|false` (does this apply to all projects?)
- `applies_to_domains: [service-desk, revops, ops-intelligence]` (which project types?)

## Learning Cycle

1. Customer A bootstraps and captures lessons (e.g., L-001, L-002)
2. Weekly observability daemon indexes them (add `customer_affected: [customerA]` to universal lessons)
3. Next Strategix project queries brain for lessons in domain → sees both Strategix + CustomerA lessons
4. Cross-customer synthesis identifies patterns (e.g., "RBAC lockout hits CustomerA too → L-018 is universal")

---

*Placeholder established 2026-04-25*
