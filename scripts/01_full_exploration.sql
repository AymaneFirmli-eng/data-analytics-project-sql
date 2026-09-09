/*
===============================================================================
DATA WAREHOUSE ANALYTICS SCRIPTS (POSTGRESQL)
Target Database: datawarehouse_analytics
Schema: gold
===============================================================================
*/


-- =============================================================================
-- 1. DATABASE & DIMENSION EXPLORATION
-- Purpose: Inspects table structures, metadata, and unique dimensions (countries, categories).
-- =============================================================================

-- Retrieve a list of all tables in the gold schema
SELECT 
    table_catalog, 
    table_schema, 
    table_name, 
    table_type
FROM information_schema.tables
WHERE table_schema = 'gold';

-- Inspect columns and data types for the customer dimension table
SELECT 
    column_name, 
    data_type, 
    is_nullable, 
    character_maximum_length
FROM information_schema.columns
WHERE table_name = 'dim_customers';

-- Retrieve a list of unique countries from which customers originate
SELECT DISTINCT 
    country 
FROM gold.dim_customers
ORDER BY country;

-- Retrieve a list of unique product categories, subcategories, and product names
SELECT DISTINCT 
    category, 
    subcategory, 
    product_name 
FROM gold.dim_products
ORDER BY category, subcategory, product_name;


-- =============================================================================
-- 2. DATE RANGE EXPLORATION & KEY METRICS
-- Purpose: Determines temporal boundaries of historical sales and calculates core business KPIs.
-- =============================================================================

-- Determine the first and last order date and the total duration in months
SELECT 
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    (EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12 + 
     EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date)))) AS order_range_months
FROM gold.fact_sales;

-- Find the oldest and youngest customers based on their birthdate and compute their age
SELECT
    MIN(birthdate) AS oldest_birthdate,
    EXTRACT(YEAR FROM AGE(MIN(birthdate))) AS oldest_age,
    MAX(birthdate) AS youngest_birthdate,
    EXTRACT(YEAR FROM AGE(MAX(birthdate))) AS youngest_age
FROM gold.dim_customers;

-- Individual Key Metric Calculations
SELECT SUM(sales_amount) AS total_sales FROM gold.fact_sales;
SELECT SUM(quantity) AS total_quantity FROM gold.fact_sales;
SELECT AVG(price) AS avg_price FROM gold.fact_sales;
SELECT COUNT(DISTINCT order_number) AS total_orders FROM gold.fact_sales;
SELECT COUNT(DISTINCT product_name) AS total_products FROM gold.dim_products;
SELECT COUNT(customer_key) AS total_customers FROM gold.dim_customers;
SELECT COUNT(DISTINCT customer_key) AS total_customers_with_orders FROM gold.fact_sales;

-- Executive Summary Report combining key metrics into a single view
SELECT 'Total Sales' AS measure_name, SUM(sales_amount)::text AS measure_value FROM gold.fact_sales
UNION ALL
SELECT 'Total Quantity', SUM(quantity)::text FROM gold.fact_sales
UNION ALL
SELECT 'Average Price', ROUND(AVG(price)::numeric, 2)::text FROM gold.fact_sales
UNION ALL
SELECT 'Total Orders', COUNT(DISTINCT order_number)::text FROM gold.fact_sales
UNION ALL
SELECT 'Total Products', COUNT(DISTINCT product_name)::text FROM gold.dim_products
UNION ALL
SELECT 'Total Customers', COUNT(customer_key)::text FROM gold.dim_customers;


-- =============================================================================
-- 3. CHANGE OVER TIME & CUMULATIVE ANALYSIS
-- Purpose: Tracks performance trends over time, monthly aggregations, and running totals.
-- =============================================================================

-- Analyze sales performance broken down by year and month
SELECT
    EXTRACT(YEAR FROM order_date) AS order_year,
    EXTRACT(MONTH FROM order_date) AS order_month,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
ORDER BY order_year, order_month;

-- Aggregate sales using PostgreSQL DATE_TRUNC function by month
SELECT
    DATE_TRUNC('month', order_date) AS order_month_trunc,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATE_TRUNC('month', order_date)
ORDER BY order_month_trunc;

-- Format order dates into custom year-month string representations
SELECT
    TO_CHAR(order_date, 'YYYY-Mon') AS order_month_formatted,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY TO_CHAR(order_date, 'YYYY-Mon')
ORDER BY MIN(order_date);

-- Calculate running totals of sales and moving average prices over time
SELECT
    order_date,
    total_sales,
    SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales,
    AVG(avg_price) OVER (ORDER BY order_date) AS moving_average_price
FROM (
    SELECT 
        DATE_TRUNC('year', order_date) AS order_date,
        SUM(sales_amount) AS total_sales,
        AVG(price) AS avg_price
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATE_TRUNC('year', order_date)
) t;


-- =============================================================================
-- 4. PERFORMANCE ANALYSIS & DATA SEGMENTATION
-- Purpose: Evaluates Year-over-Year (YoY) performance and segments products/customers.
-- =============================================================================

-- Analyze yearly product performance with YoY growth trends and deviations from product averages
WITH yearly_product_sales AS (
    SELECT
        EXTRACT(YEAR FROM f.order_date) AS order_year,
        p.product_name,
        SUM(f.sales_amount) AS current_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY 
        EXTRACT(YEAR FROM f.order_date),
        p.product_name
)
SELECT
    order_year,
    product_name,
    current_sales,
    AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,
    CASE 
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
        ELSE 'Avg'
    END AS avg_change,
    LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS py_sales,
    current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_py,
    CASE 
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
        ELSE 'No Change'
    END AS py_change
FROM yearly_product_sales
ORDER BY product_name, order_year;

-- Segment products into custom cost buckets and count totals per category
WITH product_segments AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE 
            WHEN cost < 100 THEN 'Below 100'
            WHEN cost BETWEEN 100 AND 500 THEN '100-500'
            WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
            ELSE 'Above 1000'
        END AS cost_range
    FROM gold.dim_products
)
SELECT 
    cost_range,
    COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;

-- Segment customers into VIP, Regular, or New behaviors based on lifetime spend and tenure
WITH customer_spending AS (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spending,
        MIN(f.order_date) AS first_order,
        MAX(f.order_date) AS last_order,
        (EXTRACT(YEAR FROM AGE(MAX(f.order_date), MIN(f.order_date))) * 12 + 
         EXTRACT(MONTH FROM AGE(MAX(f.order_date), MIN(f.order_date)))) AS lifespan
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c
        ON f.customer_key = c.customer_key
    GROUP BY c.customer_key
)
SELECT 
    customer_segment,
    COUNT(customer_key) AS total_customers
FROM (
    SELECT 
        customer_key,
        CASE 
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customer_spending
) AS segmented_customers
GROUP BY customer_segment
ORDER BY total_customers DESC;


-- =============================================================================
-- 5. PART-TO-WHOLE ANALYSIS & CUSTOMER REPORT VIEW
-- Purpose: Evaluates category contribution shares and builds the gold.report_customers view.
-- =============================================================================

-- Calculate the percentage contribution of each product category to total overall sales
WITH category_sales AS (
    SELECT
        p.category,
        SUM(f.sales_amount) AS total_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON p.product_key = f.product_key
    GROUP BY p.category
)
SELECT
    category,
    total_sales,
    SUM(total_sales) OVER () AS overall_sales,
    ROUND((total_sales::numeric / SUM(total_sales) OVER ()) * 100, 2) AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;

-- Drop and recreate the comprehensive customer report view for downstream analytics and reporting
DROP VIEW IF EXISTS gold.report_customers;

CREATE VIEW gold.report_customers AS

WITH base_query AS (
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.sales_amount,
        f.quantity,
        c.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        EXTRACT(YEAR FROM AGE(c.birthdate)) AS age
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c
        ON c.customer_key = f.customer_key
    WHERE order_date IS NOT NULL
)
, customer_aggregation AS (
    SELECT 
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number) AS total_orders,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT product_product_key) AS total_products,
        MAX(order_date) AS last_order_date,
        (EXTRACT(YEAR FROM AGE(MAX(order_date), MIN(order_date))) * 12 + 
         EXTRACT(MONTH FROM AGE(MAX(order_date), MIN(order_date)))) AS lifespan
    FROM base_query
    GROUP BY 
        customer_key,
        customer_number,
        customer_name,
        age
)
SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    CASE 
         WHEN age < 20 THEN 'Under 20'
         WHEN age BETWEEN 20 AND 29 THEN '20-29'
         WHEN age BETWEEN 30 AND 39 THEN '30-39'
         WHEN age BETWEEN 40 AND 49 THEN '40-49'
         ELSE '50 and above'
    END AS age_group,
    CASE 
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,
    last_order_date,
    (EXTRACT(YEAR FROM AGE(CURRENT_DATE, last_order_date)) * 12 + 
     EXTRACT(MONTH FROM AGE(CURRENT_DATE, last_order_date))) AS recency,
    total_orders,
    total_sales,
    total_quantity,
    total_products,
    lifespan,
    CASE WHEN total_orders = 0 THEN 0
         ELSE total_sales / total_orders
    END AS avg_order_value,
    CASE WHEN lifespan = 0 THEN total_sales
         ELSE total_sales / lifespan
    END AS avg_monthly_spend
FROM customer_aggregation;
