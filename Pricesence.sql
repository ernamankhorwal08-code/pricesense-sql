

-- ============================================================
-- SECTION 1: MASTER INITIALIZATION & OVERWRITE LAYER
-- ============================================================

DROP VIEW IF EXISTS master_view;


-- ============================================================
-- SECTION 2: LOGICAL DATA ARCHITECTURE — MASTER JOINED VIEW
-- ============================================================

CREATE VIEW master_view AS
SELECT
    t.order_id,
    t.user_id,
    t.product_id,
    CAST(t.price    AS REAL)    AS price,
    CAST(t.quantity AS INTEGER) AS quantity,
    t.timestamp,
    t.channel,
    p.category,
    p.claims                    AS trend_tags,
    c.persona,
    g.state,
    g.city_tier,
    g.occasion                  AS consumption_occasion
FROM transactions        t
JOIN product_metadata   p ON t.product_id = p.product_id
JOIN consumer_insights  c ON t.user_id    = c.user_id
JOIN geography_occasion g ON t.order_id   = g.order_id
WHERE t.price    > 0
  AND t.quantity > 0;


-- ============================================================
-- SECTION 3: PHASE 1 — PRICING SENSITIVITY FRAMEWORK
-- ============================================================

-- Query 1.1 | Macro Volumetric Elasticity — Overall Demand Curve & Threshold Detection
-- Bins prices into $50 buckets; uses LAG to measure inter-bucket demand decay.
-- Elasticity proxy = (% change in quantity) / (% change in price midpoint).

WITH bucket_demand AS (
    SELECT
        CAST(price / 50 AS INTEGER) * 50              AS price_bucket,
        SUM(quantity)                                  AS total_demand,
        COUNT(order_id)                                AS transaction_count,
        ROUND(AVG(price), 2)                           AS avg_realized_price
    FROM master_view
    GROUP BY price_bucket
),
elasticity_calc AS (
    SELECT
        price_bucket,
        total_demand,
        transaction_count,
        avg_realized_price,
        LAG(total_demand)       OVER (ORDER BY price_bucket) AS prev_demand,
        LAG(avg_realized_price) OVER (ORDER BY price_bucket) AS prev_avg_price
    FROM bucket_demand
)
SELECT
    price_bucket,
    total_demand,
    transaction_count,
    avg_realized_price,
    prev_demand,
    CASE
        WHEN prev_demand IS NULL OR prev_demand = 0 THEN NULL
        ELSE ROUND((CAST(total_demand - prev_demand AS REAL) / prev_demand) * 100, 2)
    END AS demand_pct_drop,
    -- First-principles elasticity proxy: %ΔQ / %ΔP
    CASE
        WHEN prev_demand IS NULL OR prev_demand = 0
          OR prev_avg_price IS NULL OR prev_avg_price = 0 THEN NULL
        ELSE ROUND(
            ( (CAST(total_demand - prev_demand AS REAL) / prev_demand) )
            /
            ( (CAST(avg_realized_price - prev_avg_price AS REAL) / prev_avg_price) ),
            4
        )
    END AS elasticity_proxy
FROM elasticity_calc
ORDER BY price_bucket;


-- Query 1.2 | Cohort Sensitivity Matrix — Persona-Partitioned Demand by Price Bucket
-- Identifies which persona (fitness / budget / premium) loses demand fastest as price rises.

WITH cohort_buckets AS (
    SELECT
        CAST(price / 50 AS INTEGER) * 50 AS price_bucket,
        persona,
        SUM(quantity)                     AS total_demand,
        COUNT(order_id)                   AS transaction_count
    FROM master_view
    GROUP BY price_bucket, persona
)
SELECT
    price_bucket,
    persona,
    total_demand,
    transaction_count,
    LAG(total_demand) OVER (
        PARTITION BY persona
        ORDER BY price_bucket
    ) AS prev_demand,
    CASE
        WHEN LAG(total_demand) OVER (PARTITION BY persona ORDER BY price_bucket) IS NULL
          OR LAG(total_demand) OVER (PARTITION BY persona ORDER BY price_bucket) = 0
        THEN NULL
        ELSE ROUND(
            (CAST(total_demand - LAG(total_demand) OVER (PARTITION BY persona ORDER BY price_bucket) AS REAL)
            / LAG(total_demand) OVER (PARTITION BY persona ORDER BY price_bucket)) * 100,
            2
        )
    END AS cohort_demand_pct_drop
FROM cohort_buckets
ORDER BY persona, price_bucket;


-- ============================================================
-- SECTION 4: PHASE 2 — CONTEXTUAL OPTIMIZATION ENGINE
-- ============================================================

-- Query 2.1 | Trend-Premium Matrix — Claim-Tier Pricing Power
-- Compares avg realized price and gross revenue for high-protein / clean-label SKUs vs baseline.

SELECT
    CASE
        WHEN trend_tags LIKE '%high-protein%' AND trend_tags LIKE '%clean-label%'
            THEN 'High-Protein + Clean-Label'
        WHEN trend_tags LIKE '%high-protein%'
            THEN 'High-Protein Only'
        WHEN trend_tags LIKE '%clean-label%'
            THEN 'Clean-Label Only'
        ELSE 'Baseline (No Premium Claim)'
    END                             AS claim_tier,
    COUNT(order_id)                 AS transaction_count,
    SUM(quantity)                   AS total_units_sold,
    ROUND(AVG(price), 2)            AS avg_realized_price,
    ROUND(SUM(price * quantity), 2) AS gross_revenue
FROM master_view
GROUP BY claim_tier
ORDER BY avg_realized_price DESC;


-- Query 2.2 | Geographic Performance Layer — State & City-Tier Pricing Velocity
-- Surfaces high-price / high-demand geographic zones for premium pricing deployment.

SELECT
    state,
    city_tier,
    COUNT(order_id)                 AS transaction_count,
    SUM(quantity)                   AS total_units_sold,
    ROUND(AVG(price), 2)            AS avg_localized_price,
    ROUND(SUM(price * quantity), 2) AS gross_revenue
FROM master_view
GROUP BY state, city_tier
ORDER BY gross_revenue DESC;


-- Query 2.3 | Occasion-Wise Behavioral Margin Index — Consumption Context Yield
-- Evaluates total units, revenue pools, and yield-per-unit for each consumption occasion.

SELECT
    consumption_occasion,
    COUNT(order_id)                                              AS transaction_count,
    SUM(quantity)                                                AS total_units_sold,
    ROUND(SUM(price * quantity), 2)                              AS gross_revenue,
    ROUND(SUM(price * quantity) / CAST(SUM(quantity) AS REAL), 2) AS yield_per_unit
FROM master_view
GROUP BY consumption_occasion
ORDER BY yield_per_unit DESC;


-- Query 2.4 | Revenue vs. Volume Optimization Frontier — Price Bucket Trade-Off Analysis
-- CTE-wrapped bucket math isolates the price point maximizing revenue vs. volume independently.

WITH price_buckets AS (
    SELECT
        CAST(price / 50 AS INTEGER) * 50 AS price_bucket,
        SUM(quantity)                     AS total_volume,
        ROUND(SUM(price * quantity), 2)   AS total_revenue,
        COUNT(order_id)                   AS transaction_count,
        ROUND(AVG(price), 2)              AS avg_price
    FROM master_view
    GROUP BY price_bucket
)
SELECT
    price_bucket,
    avg_price,
    total_volume,
    total_revenue,
    transaction_count,
    RANK() OVER (ORDER BY total_volume  DESC) AS volume_rank,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
    -- Strategic divergence flag: buckets where revenue rank and volume rank diverge sharply
    CASE
        WHEN ABS(
            RANK() OVER (ORDER BY total_revenue DESC) -
            RANK() OVER (ORDER BY total_volume  DESC)
        ) >= 3 THEN 'HIGH DIVERGENCE — Strategic Decision Required'
        ELSE 'Aligned'
    END AS optimization_signal
FROM price_buckets
ORDER BY price_bucket;

-- ============================================================
-- END OF PRICESENSE ANALYTICAL CODEBASE
-- ============================================================