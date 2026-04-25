# RBAC Lockout Findings

Issues with role-based access control, permission inheritance, and access violations.

## Common Patterns

- **D-005:** Inline role arrays in routes/components (should be centralized in RBAC source of truth)
- **D-006:** Silent RBAC inheritance (permissions not explicitly checked)
- **D-007:** Circular role dependencies (role A includes B includes A)
- **D-008:** Permission scope drift (route claims to require role X, but checks for role Y)

## Related Lessons

- [[strategix-L-018]] — Centralized RBAC, forbidden inline arrays
- [[strategix-L-019]] — (variant) Multi-tenant RBAC considerations

---

*RBAC lockout findings category established 2026-04-25*
