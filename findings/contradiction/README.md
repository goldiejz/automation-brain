# Contradiction Findings

Issues with documentation/code drift, misaligned expectations, and truth hierarchy violations.

## Common Patterns

- **D-013:** STATE.md claims feature X is shipped, but code doesn't implement it
- **D-014:** CLAUDE.md describes convention Y, but linter doesn't enforce it
- **D-015:** Project says "use Drizzle for migrations", but code uses raw SQL
- **D-016:** README says "read lessons before starting", but onboarder didn't find lessons.md

## Related Lessons

- [[strategix-L-012]] — Truth hierarchy: STATE.md is primary, CLAUDE.md is secondary
- [[strategix-L-013]] — Doc/code drift is a defect, not a footnote

## Contradiction Detection

When a contradiction is found:
1. Identify which source is wrong (code or doc)
2. Fix the source that's out of date
3. Update [[observability/cross-customer-insights]] if pattern is cross-project
4. Cite the lesson that would have prevented this

---

*Contradiction findings category established 2026-04-25*
