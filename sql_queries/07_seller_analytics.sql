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
