---
name: composer-tables
description: How to write composer gt clinical tables; named CSR templates.
applies_to: [function_block]
extra_field: ignored by the parser
---

# Composer tables

Use the `composer` package to build clinical tables. Templates live in
`templates/`. To use one, read it with `read_skill_file` and set the block's
`fn` to its contents.

Available templates:

- `templates/DEMO_T_001.R` — demographics summary table.
