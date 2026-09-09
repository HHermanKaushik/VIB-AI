# Local migration review tool

Run from the repository root:

```bash
python3 review_tool.py
```

Open <http://127.0.0.1:8765/>. The tool loads `needs_review` records from `migration_output/organizations.jsonl` and joins each record's `provenance.sourceRow` to the original CSV so staff can compare raw and normalized values. Controlled organization types and service codes are rendered as checkboxes.

Saving a record as verified or rejected writes it to `migration_output/organizations_reviewed.jsonl`. The original JSONL is never overwritten. On restart, records already present in the reviewed file are excluded from the open queue. Stop with `Ctrl-C`.