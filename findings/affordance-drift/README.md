# Affordance Drift Findings

Issues with shell rebuild, interface consistency, and platform affordance changes.

## Common Patterns

- **D-009:** Cloudflare Pages vs Workers divergence (API not available in one or the other)
- **D-010:** Shell module rebuild cost underestimated (shell change requires more than expected)
- **D-011:** Worker/Page binding mismatch (code assumes binding exists, not deployed)
- **D-012:** Environment variable misalignment (dev vs staging vs prod)

## Related Lessons

- [[strategix-L-020]] — Affordance audit and shell rebuild costs
- [[strategix-L-023]] — (variant) Domain-specific affordance (e.g., timesheet affordances)

---

*Affordance drift findings category established 2026-04-25*
