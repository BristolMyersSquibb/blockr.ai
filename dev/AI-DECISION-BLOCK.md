# Concept: AI Decision Block

## Overview

A simple block type that uses an LLM to process data within a workflow. Unlike the AI Assistant (which helps configure blocks), the AI Decision Block is a block itself - it lives inside the data flow and processes data.

## Distinction from AI Assistant

| Concept | Role | When it runs |
|---------|------|--------------|
| **AI Assistant** | Helps configure blocks/workflows | On user request |
| **AI Decision Block** | Processes data with LLM | As part of data flow |

## What It Does

```
[data] → [AI Decision Block] → [enriched data]
              │
        Prompt: "Classify each row"
                "Flag anomalies"
                "Summarize trends"
```

The AI Decision Block:
- Takes input data (like any block)
- Takes a prompt describing what to do
- Calls LLM with data + prompt
- Returns modified/enriched data

## Use Cases

| Use Case | Input | Prompt | Output |
|----------|-------|--------|--------|
| **Classification** | Customer feedback | "Classify as positive/negative/neutral" | Data + sentiment column |
| **Anomaly detection** | Sales data | "Flag unusual patterns" | Data + anomaly flag |
| **Summarization** | Daily metrics | "Summarize key trends" | Summary row/text |
| **Extraction** | Text documents | "Extract key entities" | Data + extracted fields |
| **Routing decision** | Any data | "Should this trigger an alert?" | Data + decision column |

## Example Workflow

```
[Read CSV] → [Filter] → [AI Decision Block] → [Output]
                              │
                        "For each row, classify
                         the urgency as low/medium/high
                         based on the description column"
```

**Input data:**
| id | description |
|----|-------------|
| 1 | Server is completely down |
| 2 | Minor typo in footer |
| 3 | Login fails for some users |

**Output data:**
| id | description | urgency | reasoning |
|----|-------------|---------|-----------|
| 1 | Server is completely down | high | Complete outage affects all users |
| 2 | Minor typo in footer | low | Cosmetic issue only |
| 3 | Login fails for some users | medium | Partial functionality loss |

## Implementation Approach

Similar to existing deterministic transform block, but:
- Focused on enrichment/classification rather than arbitrary code
- Could process row-by-row or entire dataset
- Returns structured output (new columns)

```r
new_ai_decision_block <- function(

prompt = "",
  output_columns = "decision",
  model = "gpt-4o-mini"
) {
  # ...
}
```

## Relation to Workflow Automation

The AI Decision Block is **independent** of workflow automation:

| Topic | AI-related? | Description |
|-------|-------------|-------------|
| AI Decision Block | Yes | Block that processes data with LLM |
| Scheduling/triggers | No | Run workflows on schedule |
| File watchers | No | Run workflows on data update |
| n8n integration | No | External workflow orchestration |

Workflow automation (scheduling, triggers) belongs to blockr.workflow, not blockr.ai. The AI Decision Block can be used in automated workflows, but the automation itself is not an AI feature.

## Next Steps

1. [ ] Design block interface (prompt input, output column config)
2. [ ] Implement using deterministic loop pattern
3. [ ] Test with classification and anomaly detection use cases
4. [ ] Consider batch vs row-by-row processing for large datasets
