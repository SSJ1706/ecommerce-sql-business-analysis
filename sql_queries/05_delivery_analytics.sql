
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
    ROUND(AVG(CAST(DATEDIFF(DAY, order_estimated_delivery_date, order_delivered_customer_date) AS FLOAT)), 2) AS avg_delay_occured,
    MAX(DATEDIFF(DAY, order_delivered_customer_date, order_estimated_delivery_date)) AS max_delay_cased
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
