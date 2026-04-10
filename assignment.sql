-------------------------------------------
Data Cleaning Queries and Data Inspection
-------------------------------------------
1. Remove empty / invalid company names

DELETE FROM customers
WHERE company_name IS NULL OR company_name = ' ';


2. Trim messy Text

UPDATE customers
SET 
  company_name = TRIM(company_name),
  country_name = TRIM(country_name);


3. Checking missing revenue 

SELECT *FROM subscriptions
WHERE mrr_usd IS NULL;

4. Fix negative and unrealistic revenue

DELETE FROM subscriptions
WHERE mrr_usd < 0;


5. validate data consistency

SELECT * FROM subscriptions
WHERE start_date < end_date;


6. Duplicate Subscriptions
SELECT customer_id,plan_id, COUNT(*)
FROM subscriptions
GROUP BY customer_id,plan_id
HAVING COUNT(*)>1;

* There are some customers with double subscriptions.

7. Missing resolution date in support_tickets

SELECT * FROM support_tickets
WHERE resolved_at IS NULL;

* Missing resolution date is considered as ticket is unresolved.

--------------------------------------------------------------------------
Assignment Queries Solution
--------------------------------------------------------------------------
1. Joins + Aggregation


SELECT p.plan_id,
  COUNT(DISTINCT(s.customer_id)) AS active_customers,
  AVG(s.mrr_usd) AS avg_monthly_revenue,
  COUNT(t.ticket_id)*1.0 / COUNT(DISTINCT s.customer_id) / 6 AS monthly_ticket_rate
FROM subscriptions s
JOIN plans p ON s.plan_id = p.plan_id
LEFT JOIN support_tickets t ON s.customer_id = t.customer_id
AND t.created_at >= NOW() - INTERVAL '6 months'
WHERE s.status = 'Active'
GROUP BY p.plan_id,p.plan_name
ORDER BY avg_monthly_revenue DESC;

--------------------------------
2. Window Function

calculate lifetime value (ltv)
rank customers for plan according to their ltv
compare customer ltv with avg ltv
show difference % 


WITH base_ltv AS (
  SELECT 
    s.customer_id,
    p.plan_tier,
    ---ltv
    SUM(s.mrr_usd) AS ltv, 
    --- avg ltv tier
    AVG(SUM(s.mrr_usd)) OVER(PARTITION BY p.plan_tier) AS avg_ltv_tier  
  FROM subscriptions s 
  JOIN plans p ON s.plan_id = p.plan_id
  GROUP BY s.customer_id, p.plan_tier
)

SELECT 
  customer_id,
  plan_tier,
  ltv,
  avg_ltv_tier,

  RANK() OVER(PARTITION BY plan_tier ORDER BY ltv DESC) AS tier_rank,
  --- % diff between ltv and tier ltv
  ((ltv - avg_ltv_tier) * 100.0 / avg_ltv_tier) AS pct_diff_bw_ltv_and_avgltv  
FROM base_ltv
ORDER BY plan_tier, tier_rank;
---------------------------------------
3. CTEs + Subqueries

WITH plan_changes AS (
    SELECT 
        s.customer_id,
        s.plan_id,
        p.plan_tier,
        s.start_date,

        -- Get the previous plan ID
        LAG(s.plan_id) OVER(
            PARTITION BY s.customer_id 
            ORDER BY s.start_date
        ) AS prev_plan_id,

        -- Get the previous plan tier 
        LAG(p.plan_tier) OVER(
            PARTITION BY s.customer_id 
            ORDER BY s.start_date
        ) AS prev_plan_tier

    FROM subscriptions s
    JOIN plans p ON s.plan_id = p.plan_id
)

SELECT 
    pc.customer_id,
    p_prev.plan_name AS previous_plan,
    p_curr.plan_name AS current_plan,
    COUNT(st.ticket_id) AS ticket_count,
    pc.start_date AS downgrade_date
FROM plan_changes pc

-- Rejoin plans to get names
JOIN plans p_prev ON pc.prev_plan_id = p_prev.plan_id
JOIN plans p_curr ON pc.plan_id = p_curr.plan_id

-- Join tickets created in the 30 days leads to the downgrade
LEFT JOIN support_tickets st 
    ON pc.customer_id = st.customer_id
    AND st.created_at >= (pc.start_date - INTERVAL '30 days')
    AND st.created_at <= pc.start_date
WHERE 
    pc.prev_plan_tier IS NOT NULL
    AND pc.prev_plan_tier > pc.plan_tier    
    AND pc.start_date >= now() - INTERVAL '90 days'
GROUP BY 
    pc.customer_id, 
    p_prev.plan_name, 
    p_curr.plan_name, 
    pc.start_date
HAVING 
    COUNT(st.ticket_id) > 3
ORDER BY 
    ticket_count DESC;

----------------------------------------------------------------------
4. Time Series
-- According to plan new and churned subscriptions
  SELECT
    DATE_TRUNC('month',s.start_date) AS month,
    p.plan_tier,
    COUNT(*) FILTER(WHERE s.status = 'active') AS new_subscriptions,
    COUNT(*) FILTER(WHERE s.status IN ('cancelled','expired')) AS churned_subscriptions
  FROM subscriptions s
  JOIN plans p on s.plan_id = p.plan_id
  GROUP BY month , p.plan_tier; 


-----------------------------------------------------------------------
5. Advanced

WITH normalized_customers AS(
  SELECT customer_id,
    LOWER(REPLACE(TRIM(company_name),'','')) AS normalized_name,
    SPLIT_PART(contact_email,'@',2) AS email_domain
  FROM customers
),

team_overlap AS(
  SELECT 
    t1.customer_id AS customer_1,
    t2.customer_id AS customer_2,
    COUNT(*) AS shared_members 
  FROM team_members t1
  JOIN team_members t2
    ON t1.email = t2.email
    AND t1.customer_id != t2.customer_id
    GROUP BY t1.customer_id , t2.customer_id
)

SELECT 
  c1.customer_id AS customer_1,
  c2.customer_id AS customer_2,
  c1.normalized_name,
  c2.normalized_name,
  c1.email_domain,
  c2.email_domain,
  COALESCE(t.shared_members,0) AS shared_members  

FROM normalized_customers c1
JOIN normalized_customers c2
  ON c1.customer_id < c2.customer_id

LEFT JOIN team_overlap t 
    ON c1.customer_id = t.customer_1
    AND c2.customer_id = t.customer_2

WHERE 
    (
      --- same names
      c1.normalized_name=c2.normalized_name
    )
    OR (
      --- same email
      c1.email_domain=c2.email_domain
    )
    OR(
      --- shared team_members
      t.shared_members >0
    )
  ORDER BY shared_members DESC;






