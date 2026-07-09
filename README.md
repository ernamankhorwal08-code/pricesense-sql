# PriceSense SQL

A structured analytical framework built for a real D2C nutrition brand to optimize pricing strategy using pure SQL — covering demand elasticity, persona segmentation, geographic performance, and revenue-volume trade-offs.

## Overview

PriceSense simulates the pricing intelligence workflow of a D2C nutrition brand (protein shakes, bars, meal replacements, electrolyte drinks, supplements) selling across marketplace, app, website, retail, and gym-kiosk channels. The project uses only SQL — views, CTEs, and window functions — to turn raw transactional data into pricing decisions, without any external BI tool or scripting layer.

## Dataset

The data lives in `Pricesence_Final.db` (SQLite) and spans five tables:

| Table | Rows | Description |
|---|---|---|
| `transactions` | 50,150 | order_id, user_id, product_id, price, quantity, timestamp, channel |
| `product_metadata` | 150 | category, claims (e.g. high-protein, clean-label), ingredient_tags, pack_size |
| `consumer_insights` | 5,000 | persona (fitness / budget / premium / casual), trend_affinity, age_group, income_bracket, dietary_restriction |
| `geography_occasion` | 47,581 | state, city_tier, consumption occasion (gym, festive, marathon-prep, road-trip, etc.) |
| `competitor_pricing` | 720 | competitor_product_id, price, timestamp |

All four core tables are joined into a single `master_view` that powers every downstream query.

## Analytical Framework

The SQL is organized into two phases:

**Phase 1 — Pricing Sensitivity Framework**
- **Macro Volumetric Elasticity**: Bins prices into $50 buckets and uses `LAG()` to compute demand decay and a first-principles elasticity proxy (%ΔQuantity / %ΔPrice) across the whole customer base.
- **Cohort Sensitivity Matrix**: Repeats the elasticity analysis partitioned by persona, to identify which customer segment (fitness / budget / premium / casual) drops off fastest as prices rise.

**Phase 2 — Contextual Optimization Engine**
- **Trend-Premium Matrix**: Measures the pricing power of product claims (high-protein, clean-label) versus baseline SKUs.
- **Geographic Performance Layer**: Ranks state and city-tier combinations by realized price and revenue to flag zones for premium pricing.
- **Occasion-Wise Behavioral Margin Index**: Computes yield-per-unit by consumption occasion (gym, festive, road-trip, etc.) to find the highest-margin contexts.
- **Revenue vs. Volume Optimization Frontier**: Uses `RANK()` window functions to compare revenue rank against volume rank per price bucket, flagging buckets with high divergence as strategic decision points.

## Tech / SQL Concepts Used

- Views (`CREATE VIEW`) for a reusable master data layer
- CTEs (`WITH`) for readable, staged transformations
- Window functions: `LAG()`, `RANK()`, `PARTITION BY`
- Conditional aggregation (`CASE WHEN`) for tiering and flagging
- Derived elasticity metrics computed natively in SQL

## Repository Contents

```
Pricesence.sql                              -- full analytical SQL codebase
Pricesence_Final.db                         -- SQLite database (source data)
PriceSense SQL Pricing Intelligence Deck.pdf -- summary deck of findings
```

## How to Run

1. Open `Pricesence_Final.db` in any SQLite client (DB Browser for SQLite, `sqlite3` CLI, TablePlus, etc.).
2. Execute `Pricesence.sql` top to bottom — it first (re)creates `master_view`, then runs each analytical query in sequence.
3. Review `PriceSense SQL Pricing Intelligence Deck.pdf` for the business-facing summary of insights and recommendations.

## Author

Naman Khorwal
