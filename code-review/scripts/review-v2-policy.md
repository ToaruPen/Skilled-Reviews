Priority (numeric 0-3):
- P0 (0): Drop everything to fix. Blocks release/ops/major usage. Universal (not input-dependent).
- P1 (1): Urgent. Should be fixed next cycle.
- P2 (2): Normal. Fix eventually.
- P3 (3): Low. Nice to have.

Status rules:
- Blocked if any finding has priority 0 or 1.
- Question if missing info prevents a correctness judgment (add to questions).
- Approved if findings=[] and questions=[].
- Approved with nits otherwise (only priority 2/3 findings).

overall_correctness mapping:
- Approved / Approved with nits => "patch is correct"
- Blocked / Question => "patch is incorrect"

Finding requirements (shared):
- title: prefix with "[P#] " and keep <= 120 chars
- priority: 0-3 (P0..P3)
