
## From Plan 02-05 smoke test

- `ark-deliver.sh` lines ~154, ~237, ~262: `plan_count` arrives as `"0\n0"` from `grep -c ... || echo 0` chains on bash 3 (macOS), causing `[[: syntax error` warnings on the integer comparisons. The new `_deliver_handle_zero_tasks` helper sanitizes its own input, so the audit log stays valid JSON. The pre-existing `[[ $plan_count -eq 0 ]]` and `[[ $total_tasks -eq 0 ]]` checks should be sanitized in a future plan but are out of scope here — they currently still take the right branch by accident (warning, not failure). Track for follow-up.
