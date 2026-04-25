# Schema Drift Findings

Issues with database schema, migrations, column definitions, and data consistency.

## Common Patterns

- **D-001:** Unsuffixed currency columns (missing _zar, _usd suffix)
- **D-002:** Unsuffixed duration columns (missing _minutes, _seconds suffix)
- **D-003:** Migration coordination across repos (when schema changes require downstream changes)
- **D-004:** NULL constraint violations (adding NOT NULL without backfill)

## Related Lessons

- [[strategix-L-021]] — Column naming conventions
- [[strategix-L-022]] — Migration coordination

---

*Schema drift findings category established 2026-04-25*
