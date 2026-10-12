
/* =========================================================
			  BRAZILIAN E-COMMERCE SQL ANALYSIS
				   Database Setup Script
   ========================================================= */

-- Create Database--
CREATE DATABASE ecommerce_analysis;
GO

USE ecommerce_analysis;
GO

/* =============================================================
							DATA IMPORT
   =============================================================

   Dataset imported using SQL Server Import and Export Wizard.

   Files imported:
   - customers.csv
   - orders.csv
   - order_items.csv
   - products.csv
   - sellers.csv
   - payments.csv
   - reviews.csv

*/

-------------------------------------- BASIC INFO ABOUT TABLES--------------------------------------------
SELECT COUNT(*) AS customers FROM customers;
SELECT COUNT(*) AS orders FROM orders;
SELECT COUNT(*) AS order_items FROM order_items;
SELECT COUNT(*) AS payments FROM payments;
SELECT COUNT(*) AS reviews FROM reviews;
SELECT COUNT(*) AS products FROM products;
SELECT COUNT(*) AS sellers FROM sellers;

SELECT TOP 5 * FROM customers;
SELECT TOP 5 * FROM sellers;
SELECT TOP 5 * FROM products;
SELECT TOP 5 * FROM order_items;
SELECT TOP 5 * FROM orders;
SELECT TOP 5 * FROM payments;
SELECT TOP 5 * FROM reviews;


-------------------------------------- Revenue Analysis-------------------------------------------

-- Basic KPI About Revenue Generation --
SELECT
    SUM(payment_value) AS total_revenue,
    AVG(payment_value) AS avg_order_value,
    MAX(payment_value) AS highest_order,
    MIN(payment_value) AS lowest_order
FROM payments;

--Making VIEW for future use & using LEFT JOIN to Merge Data for Revenue Analysis --
DROP VIEW IF EXISTS V_orders_enriched;
GO
CREATE VIEW V_orders_enriched AS 
    SELECT  
        o.order_id,
        o.customer_id,
        FORMAT(o.order_purchase_timestamp,'yyyy-MM') AS order_month,
        o.order_delivered_customer_date AS delivery_date,
        o.order_status,
        p.payment_value
    FROM payments AS p
    LEFT JOIN orders AS o
        ON p.order_id = o.order_id;

-- Monthly Revenue Generated --
SELECT
    order_month,
    SUM(payment_value) AS monthly_revenue
FROM V_orders_enriched
GROUP BY order_month
ORDER BY order_month;

-- Monthly Growth % --
WITH monthly_summary AS
(
    SELECT
        order_month,
        SUM(payment_value) AS monthly_revenue
    FROM V_orders_enriched
    GROUP BY order_month
),
monthly_growth AS
(
    SELECT
        order_month,
        monthly_revenue,
        LAG(monthly_revenue,1) OVER(ORDER BY order_month) AS previous_month_revenue
    FROM monthly_summary
)
SELECT
    order_month,
    monthly_revenue,
    previous_month_revenue,
    ROUND((monthly_revenue - previous_month_revenue)* 100.0 / previous_month_revenue, 3) AS percentage_change_in_revenue
FROM monthly_growth;

--Top Months in Revenue Generation--
SELECT TOP 5
    order_month,
    SUM(payment_value) AS monthly_revenue
FROM V_orders_enriched
GROUP BY order_month
ORDER BY monthly_revenue DESC ;

--Worst Months in Revenue Generation--
SELECT TOP 5
    order_month,
    SUM(payment_value) AS monthly_revenue
FROM V_orders_enriched
GROUP BY order_month
ORDER BY monthly_revenue;


-------------------------------------- Customer Analysis-------------------------------------------

--Unique Customers--
SELECT COUNT(DISTINCT customer_unique_id) AS no_of_unique_customers
FROM customers;

--Making VIEW for future use & using LEFT JOIN to Merge Data for Customers Analysis --
DROP VIEW IF EXISTS V_customer_analytics;
GO
CREATE VIEW V_customer_analytics AS
SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_id,
    p.payment_type,
    p.payment_value
FROM orders o
LEFT JOIN customers c
    ON o.customer_id = c.customer_id
LEFT JOIN payments p
    ON o.order_id = p.order_id;

--Top Customers by Revenue--
SELECT TOP 10
    customer_unique_id,
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM V_customer_analytics
GROUP BY customer_unique_id
ORDER BY total_revenue DESC;

--Revenue by State--
SELECT
    customer_state,
    SUM(payment_value) AS total_revenue
FROM V_customer_analytics
GROUP BY customer_state
ORDER BY total_revenue DESC;

--Customers by State--
SELECT
    customer_state,
    COUNT(DISTINCT customer_unique_id) AS total_customers
FROM V_customer_analytics
GROUP BY customer_state
ORDER BY total_customers DESC;

--Prefered Payment Method--
SELECT
    COALESCE(payment_type, 'not_defined') AS payment_type,
    COUNT(*) AS total_transactions,
    ROUND(COALESCE(SUM(payment_value), 0), 2) AS total_revenue
FROM V_customer_analytics
GROUP BY COALESCE(payment_type, 'not_defined')
ORDER BY total_revenue DESC;

--High Value Customers Based on Expenditure Done by Them and No of Order --
SELECT
    customer_unique_id,
    ROUND(SUM(payment_value), 2) AS total_revenue,
    COUNT(DISTINCT order_id) AS total_orders
FROM V_customer_analytics
GROUP BY customer_unique_id
HAVING SUM(payment_value) > 1000
ORDER BY total_revenue DESC;

--Fraction of Customers with more than 1 order--
WITH customer_level AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS total_orders
    FROM V_customer_analytics
    WHERE customer_unique_id IS NOT NULL
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    SUM(CASE WHEN total_orders = 1 THEN 1 ELSE 0 END) AS one_time_customers,
    CAST(100.0 * SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0) AS DECIMAL(6,2)) AS repeat_customer_percentage
FROM customer_level;

-- Revenue contribution of repeat customers--
WITH customer_summary AS (
    SELECT
        customer_unique_id,
        COUNT(DISTINCT order_id) AS total_orders,
        SUM(payment_value) AS total_revenue
    FROM V_customer_analytics
    GROUP BY customer_unique_id
),
repeat_customer_revenue AS
(
    SELECT
        COUNT(*) AS repeat_customer_count,
        SUM(total_orders) AS repeat_customer_orders,
        SUM(total_revenue) AS repeat_customer_revenue
    FROM customer_summary
    WHERE total_orders > 1
)
SELECT
    repeat_customer_count,
    repeat_customer_orders,
    CAST(
        repeat_customer_revenue AS DECIMAL(18,2)
    ) AS repeat_customer_revenue,
    CAST(
        100.0 * repeat_customer_revenue / NULLIF((SELECT SUM(total_revenue) FROM customer_summary), 0)
        AS DECIMAL(6,2)
    ) AS repeat_customer_revenue_share_pct
FROM repeat_customer_revenue;



-------------------------------------- Delivery Analysis-------------------------------------------

-----------------------Joining orders and customers table to preview data--------------------------
-----------------------Making VIEW for future use for Delivery Analysis ---------------------------

DROP VIEW IF EXISTS V_delivery_analytics;
GO

CREATE VIEW V_delivery_analytics AS
    SELECT 
        o.order_id,
        o.customer_id,
        o.order_purchase_timestamp,
        COALESCE(o.order_approved_at, o.order_purchase_timestamp) AS order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        DATEDIFF(DAY, o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
        c.customer_state
    FROM orders o
    LEFT JOIN customers c
        ON o.customer_id = c.customer_id
    WHERE order_delivered_customer_date IS NOT NULL;

--Average, Min and Max Delivery Time--
SELECT
    ROUND(AVG(CAST(delivery_days AS FLOAT)),2) AS avg_delivery_days,
    MIN(delivery_days) AS min_delivery_days_taken,
    MAX(delivery_days) AS max_delivery_days_taken
FROM V_delivery_analytics;

--Fastest Delivery States--
SELECT TOP 10
    customer_state,
    ROUND(AVG(CAST(delivery_days AS FLOAT)),2) AS avg_delivery_days
FROM V_delivery_analytics
GROUP BY customer_state
ORDER BY avg_delivery_days ASC;

--Slowest Delivery States--
SELECT TOP 10
    customer_state,
    ROUND(AVG(CAST(delivery_days AS FLOAT)),2) AS avg_delivery_days
FROM V_delivery_analytics
GROUP BY customer_state
ORDER BY avg_delivery_days DESC;

--Late Deliveries--
SELECT
    COUNT(*) AS late_orders
FROM orders
WHERE order_delivered_customer_date > order_estimated_delivery_date;

--Amount Of Delay Caused--
SELECT
    order_id,
    DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS delay_occured
FROM V_delivery_analytics

--Percentage Late Orders--
SELECT
    ROUND(100.0 * SUM(
        CASE
            WHEN order_delivered_customer_date > order_estimated_delivery_date THEN 1
            ELSE 0
        END
        ) / COUNT(*), 2) AS late_delivery_percentage
FROM orders
WHERE order_delivered_customer_date IS NOT NULL;

/* approximately 1.18% of orders contained inconsistent timestamps where carrier handoff was recorded before approval.
These records were excluded from seller performance analysis.*/

SELECT
    order_id,
    order_approved_at,
    order_delivered_carrier_date
FROM V_delivery_analytics
WHERE order_delivered_carrier_date < order_approved_at; /*This'll give info around the orders with time based discrepancy*/

--Payments verification processing time per order--
SELECT
    order_id,
    DATEDIFF(MINUTE, order_purchase_timestamp, order_approved_at) AS payment_processing_time
FROM V_delivery_analytics
WHERE order_approved_at >= order_purchase_timestamp
ORDER BY payment_processing_time

--Average payments verification processing time--
SELECT
    AVG(DATEDIFF(MINUTE, order_purchase_timestamp, order_approved_at)) AS avg_processing_time
FROM V_delivery_analytics
WHERE order_approved_at >= order_purchase_timestamp


--Average Shipping Time--
SELECT
    ROUND(AVG(CAST(DATEDIFF(DAY, order_delivered_carrier_date, order_delivered_customer_date) AS FLOAT)), 2) AS avg_shipping_time
FROM V_delivery_analytics
WHERE order_delivered_customer_date >= order_delivered_carrier_date;

--Average Shipping Time acc to States--
SELECT
    customer_state,
    ROUND(AVG(CAST(DATEDIFF(DAY, order_approved_at, order_delivered_customer_date) AS FLOAT)), 2) AS avg_shipping_time
FROM V_delivery_analytics
WHERE order_delivered_customer_date >= order_approved_at
GROUP BY customer_state
ORDER BY avg_shipping_time;

--Shipping Time per Order--
SELECT
    order_id,
    order_delivered_customer_date,
    order_approved_at,
    DATEDIFF(DAY, order_approved_at, order_delivered_customer_date) AS shipping_time
FROM V_delivery_analytics
WHERE order_delivered_customer_date >= order_approved_at;

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders
FROM V_delivery_analytics;


--------------------------------------- Product Analysis-------------------------------------------

--------------------Joining order_items and products table to preview data-------------------------
-----------------------Making VIEW for future use for Product Analysis ----------------------------

DROP VIEW IF EXISTS V_product_analysis
GO

CREATE VIEW V_product_analysis AS
    SELECT
        oi.order_id,
        oi.product_id,
        prod.product_category_name,
        oi.price,
        oi.freight_value,
        prod.product_weight_g,
        prod.product_length_cm,
        prod.product_width_cm,
        product_height_cm
    FROM order_items oi
    LEFT JOIN products prod
        ON oi.product_id = prod.product_id;

--AVG, MAX AND MIN Prod Price--
SELECT
    MAX(price) AS max_product_price,
    ROUND(MIN(price), 2) AS min_product_price,
    ROUND(AVG(price), 2) AS avg_product_price
FROM V_product_analysis

--Most Selling Product Categories--
SELECT TOP 10
    product_category_name,
    COUNT(*) AS orders_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY orders_per_category DESC;

--Most Selling Products--
SELECT TOP 10
    product_id,
    COUNT(*) AS orders_per_product
FROM V_product_analysis
GROUP BY product_id
ORDER BY orders_per_product DESC;

--Least Selling Product Categories--
SELECT TOP 10
    product_category_name,
    COUNT(*) AS orders_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY orders_per_category;

--Least Selling Products--
SELECT TOP 10
    product_id,
    COUNT(*) AS orders_per_product
FROM V_product_analysis
GROUP BY product_id
ORDER BY orders_per_product; 

/*There are 18117 Products which were sold only Once therefore analysing least selling products doesn't make sense*/

--Frequency Distribution of Number of Products--
SELECT
    COUNT(orders_per_product) AS product_count,
    orders_per_product
FROM 
(
SELECT
    COUNT(*) AS orders_per_product
FROM V_product_analysis
GROUP BY product_id
)tt
GROUP BY orders_per_product
ORDER BY orders_per_product;

--Product Categories Generating Most Revenue--
SELECT TOP 10
    product_category_name,
    ROUND(SUM(price), 2) AS revenue_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY revenue_per_category DESC;

--Product Categories Generating Least Revenue--
SELECT TOP 10
    product_category_name,
    ROUND(SUM(price), 2) AS revenue_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY revenue_per_category;

--Product Categories With Highest Avg Prices Per Product--
SELECT TOP 10
    COALESCE(product_category_name, 'other Category') AS product_category,
    ROUND(AVG(price), 2) AS avg_product_price_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY avg_product_price_per_category DESC;

--Product Categories With Lowest Avg Prices Per Product--
SELECT TOP 10
    COALESCE(product_category_name, 'other Category') AS product_category,
    ROUND(AVG(price), 2) AS avg_product_price_per_category
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY avg_product_price_per_category;

--Highest Avg Freight Cost Category--
SELECT TOP 10
    product_category_name,
    ROUND(AVG(freight_value), 2) AS avg_freight_cost
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY avg_freight_cost DESC;

--Lowest Avg Freight Cost Category--
SELECT TOP 10
    product_category_name,
    ROUND(AVG(freight_value), 2) AS avg_freight_cost
FROM V_product_analysis
GROUP BY product_category_name
ORDER BY avg_freight_cost;

--% Freight Cost Compared to Product Price--
SELECT 
    product_category_name,
    AVG(100 * freight_value / price) AS avg_percentage_freight_cost
FROM V_product_analysis
WHERE product_category_name IS NOT NULL
GROUP BY product_category_name
ORDER BY avg_percentage_freight_cost;

--Freight Cost Compared To Weight And Dimesions--
SELECT
    CASE
        WHEN product_weight_g > 10000 THEN 'Heavy'
        WHEN product_weight_g > 1000 THEN 'Medium'
        ELSE 'Light' 
    END AS weight_category,
    ROUND(AVG(freight_value), 2) AS avg_freight_cost
FROM V_product_analysis
WHERE product_weight_g != 0
GROUP BY CASE
        WHEN product_weight_g > 10000 THEN 'Heavy'
        WHEN product_weight_g > 1000 THEN 'Medium'
        ELSE 'Light' 
    END;


--------------------------------------- Seller Analysis--------------------------------------------

------------Joining order_items, orders, sellers and products table to preview data----------------
---------------------Making VIEW for future use for Product Analysis ------------------------------
DROP VIEW IF EXISTS V_sellers_analysis
GO
CREATE VIEW V_sellers_analysis AS
    SELECT 
        o.order_id,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        prod.product_id,
        COALESCE(prod.product_category_name, 'other category') AS product_category,
        oi.price,
        s.seller_id,
        s.seller_state
    FROM orders o
    LEFT JOIN order_items oi
        ON o.order_id = oi.order_id
    LEFT JOIN products prod
        ON oi.product_id = prod.product_id
    LEFT JOIN sellers s
        ON oi.seller_id = s.seller_id
    WHERE s.seller_id IS NOT NULL;

--Sellers with most orders--
SELECT TOP 10
    seller_id,
    COUNT(DISTINCT order_id) AS number_of_orders_per_seller
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY number_of_orders_per_seller DESC;

--Sellers with least orders--
SELECT
    seller_id,
    COUNT(DISTINCT order_id) AS number_of_orders_per_seller
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY number_of_orders_per_seller;

--Seller Based Revenue Distribution--
SELECT
    seller_id,
    ROUND(SUM(price), 2) AS revenue_per_seller
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY revenue_per_seller DESC;

--Top 10% Sellers' Revenue concentration--
WITH seller_based_revenue AS 
    (
    SELECT
        seller_id,
        ROUND(SUM(price), 2) AS revenue_per_seller,
        CUME_DIST() OVER (ORDER BY ROUND(SUM(price), 2) DESC) * 100 AS percentile_rank_of_sellers
    FROM V_sellers_analysis
    GROUP BY seller_id
    ),
total_revenue_top_sellers AS
    (
    SELECT
        ROUND(SUM(revenue_per_seller), 2) AS total_revenue_of_top_sellers
    FROM seller_based_revenue
    WHERE percentile_rank_of_sellers < 10
    ),
total_revenue AS
    (
    SELECT
        SUM(revenue_per_seller) AS total_revenue_generated
    FROM seller_based_revenue
    )
SELECT
    ROUND((100 * total_revenue_of_top_sellers / total_revenue_generated), 2) AS percentage_revenue_concentration
FROM total_revenue_top_sellers
CROSS JOIN total_revenue

/*Top 10% of sellers contribute ~67.5% of total marketplace revenue, 
indicating a highly concentrated seller ecosystem 
where a small fraction of sellers drive the majority of sales.*/

--Avg Order Value (AOV) wrt seller as the grain instead of no of orders--
SELECT
    seller_id,
    ROUND(AVG(price), 2) AS avg_revenue_per_seller
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY avg_revenue_per_seller DESC;

--State based seller distribution--
SELECT
    COUNT(seller_id) AS no_of_sellers,
    seller_state
FROM V_sellers_analysis
GROUP BY seller_state
ORDER BY no_of_sellers DESC;

--Product variety per seller--
SELECT
    seller_id,
    COUNT(product_id) AS no_of_products
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY no_of_products DESC;

--Multi-Category Seller--
SELECT
    seller_id,
    COUNT(DISTINCT(product_category)) AS no_of_product_categories
FROM V_sellers_analysis
GROUP BY seller_id
ORDER BY no_of_product_categories DESC;

--Seller Handoff Time Taken To Evaluate Delays That Might Be Occuring Due To Sellers--
SELECT
    seller_id,
    AVG(DATEDIFF(DAY, order_approved_at, order_delivered_carrier_date)) AS avg_seller_handoff_time
FROM V_sellers_analysis
WHERE order_delivered_carrier_date >= order_approved_at
GROUP BY seller_id
ORDER BY avg_seller_handoff_time DESC;


--------------------------------------- Review Analysis--------------------------------------------

------------Joining order_items, orders, sellers and products table to preview data----------------
----------------------Making VIEW for future use for Review Analysis ------------------------------
DROP VIEW IF EXISTS V_review_analysis
GO
CREATE VIEW V_review_analysis AS
    SELECT 
        o.order_id,
        seller_id,
        prod.product_id,
        review_id,
        prod.product_category_name,
        r.review_score,
        r.review_creation_date,
        r.review_answer_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
FROM reviews r
LEFT JOIN orders o
    ON r.order_id = o.order_id
LEFT JOIN order_items oi
    ON o.order_id = oi.order_id
LEFT JOIN products prod
    ON oi.product_id = prod.product_id

--Avg Review Score of entire e-commerce market, Number of products rated all the different values--
SELECT
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_review_score
FROM V_review_analysis;

--Distribution of Rating v/s No of Orders--
SELECT  
    COUNT(DISTINCT(order_id)) AS no_of_orders,
    review_score AS ratings,
    CASE
        WHEN review_score IN (4,5) THEN 'Positive Review'
        WHEN review_score = 3 THEN 'Neutral'
        WHEN review_score IN (1,2) THEN 'Negative Review'
        ELSE 'N/A'
    END AS customer_satisfaction
FROM V_review_analysis
GROUP BY review_score
ORDER BY ratings;

--Category Wise Rating Distribution--
SELECT 
    COALESCE(product_category_name, 'other_items'),
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_category_rating
FROM V_review_analysis
GROUP BY product_category_name
ORDER BY avg_category_rating DESC;

--Seller Wise Rating Distribution--
SELECT
    seller_id,
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_category_rating
FROM V_review_analysis
GROUP BY seller_id
ORDER BY avg_category_rating DESC;

--Delivery Time v/s Reviews--
SELECT
    CASE
        WHEN delivery_days <= 7 THEN 'Fast (<=7 Days)'
        WHEN delivery_days <= 14 THEN 'Medium (8-14 Days)'
        ELSE 'Slow (>14 Days)'
    END AS delivery_speed,
    ROUND(AVG(CAST(review_score AS FLOAT)), 2) AS avg_review_score,
    COUNT(*) AS total_orders
FROM V_review_analysis v
LEFT JOIN V_delivery_analytics d
    ON v.order_id = d.order_id
GROUP BY
    CASE
        WHEN delivery_days <= 7 THEN 'Fast (<=7 Days)'
        WHEN delivery_days <= 14 THEN 'Medium (8-14 Days)'
        ELSE 'Slow (>14 Days)'
    END
ORDER BY avg_review_score DESC;
