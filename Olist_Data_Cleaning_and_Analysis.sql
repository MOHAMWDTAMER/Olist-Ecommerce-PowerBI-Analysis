/*
Project: Olist E-commerce Data Cleaning & ETL
Description: This script performs comprehensive data cleaning on the Brazilian Olist Dataset.
             Steps include: Handling Nulls, Outlier removal, Consistency checks, 
             Feature Engineering (Delivery Status), and Final Table .
*/

USE [brazilian sales];

-----------------------------------------------------------
-- 1. CUSTOMERS DATA CLEANING
-----------------------------------------------------------

-- Initial exploration
SELECT TOP 100 * FROM olist_customers_dataset;

-- Checking for NULL values in Customer table
SELECT 
    COUNT(*) AS total_row,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS id_nulls,
    SUM(CASE WHEN customer_unique_id IS NULL THEN 1 ELSE 0 END) AS unique_id_nulls,
    SUM(CASE WHEN customer_city IS NULL THEN 1 ELSE 0 END) AS city_nulls,
    SUM(CASE WHEN customer_state IS NULL THEN 1 ELSE 0 END) AS state_nulls
FROM olist_customers_dataset;

-- Checking for Duplicates in customer_id
SELECT customer_id, COUNT(*)
FROM olist_customers_dataset
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- Standardizing consistency (Cities to lowercase)
-- Creating Clean Customer Table
SELECT 
    customer_id,
    customer_unique_id,
    customer_state,
    TRIM(LOWER(customer_city)) AS customer_city
INTO clean_customers_table
FROM olist_customers_dataset;

-----------------------------------------------------------
-- 2. ORDERS DATA CLEANING & FEATURE ENGINEERING
-----------------------------------------------------------

-- Checking for logic errors in delivery dates (Delivered orders with no delivery date)
SELECT 
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS Missing_Delivery_date,
    SUM(CASE WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS error_logic_nulls
FROM olist_orders_dataset;

-- Creating Clean Orders Table (Filtering only valid delivered orders)
SELECT * INTO clean_orders_table
FROM olist_orders_dataset
WHERE order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL;

-- Feature Engineering: Calculating Actual vs Estimated Delivery Days
ALTER TABLE clean_orders_table 
ADD Actual_Delivery_Days INT, Estimated_Delivery_Days INT;

UPDATE clean_orders_table
SET Actual_Delivery_Days = DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date),
    Estimated_Delivery_Days = DATEDIFF(DAY, order_delivered_customer_date, order_estimated_delivery_date);

-- Handling Outliers (Removing delivery periods > 60 days)
DELETE FROM clean_orders_table
WHERE Actual_Delivery_Days > 60;

-- Checking for chronological logic errors (Delivery before purchase)
SELECT COUNT(*) AS logic_error
FROM clean_orders_table
WHERE order_delivered_customer_date < order_purchase_timestamp;

-- Categorizing Delivery Status (On Time vs Late)
ALTER TABLE [dbo].[clean_orders_table]
ADD Delivery_status VARCHAR(20);

UPDATE clean_orders_table 
SET Delivery_status = 
    CASE 
        WHEN Actual_Delivery_Days <= Estimated_Delivery_Days THEN 'On Time'
        WHEN Actual_Delivery_Days > Estimated_Delivery_Days THEN 'Late'
        ELSE 'Unknown'
    END;

-----------------------------------------------------------
-- 3. PRODUCTS & CATEGORY TRANSLATION
-----------------------------------------------------------

-- Merging products with English translations and handling Nulls
SELECT 
    P.product_id,
    ISNULL(T.[product_category_name_english], 'Unknown') AS category_name_en,
    ISNULL(P.product_weight_g, 0) AS product_weight,
    ISNULL(P.product_length_cm, 0) * ISNULL(P.product_height_cm, 0) * ISNULL(P.product_width_cm, 0) AS product_volume_cm
INTO clean_products_table
FROM olist_products_dataset P
LEFT JOIN [dbo].[product_category_name_translation] T
ON P.product_category_name = T.[product_category_name];

-----------------------------------------------------------
-- 4. PAYMENTS & REVIEWS CLEANING
-----------------------------------------------------------

-- Aggregating payments per order and filtering invalid values
SELECT 
    order_id,
    SUM(payment_value) AS total_values,
    MAX(payment_installments) AS max_installments,
    MAX(payment_type) AS main_payment_method
INTO clean_payments_table
FROM olist_order_payments_dataset
WHERE payment_value > 0 AND payment_type <> 'not_defined'
GROUP BY order_id;

-- Handling Duplicate Reviews by keeping the latest review per order
WITH RankedReviews AS (
    SELECT 
        review_id, order_id, review_score,
        ISNULL(review_comment_message, 'No Comment') AS review_comment,
        review_creation_date,
        ROW_NUMBER() OVER(PARTITION BY order_id ORDER BY review_creation_date DESC) AS row_num
    FROM olist_order_reviews_dataset
)
SELECT review_id, order_id, review_score, review_comment, review_creation_date
INTO clean_reviews_table
FROM RankedReviews
WHERE row_num = 1;

-----------------------------------------------------------
-- 5. FINAL  TABLE 
-----------------------------------------------------------

-- Joining all cleaned tables into one Table for Power BI
SELECT 
    O.order_id, O.customer_id, O.order_status, O.order_purchase_timestamp,
    O.Actual_Delivery_Days, O.Delivery_status,
    C.customer_city, C.customer_state,
    P.category_name_en, P.product_weight, P.product_volume_cm,
    I.price, I.freight_value,
    S.seller_id, S.seller_city, S.seller_state,
    PAY.total_values, PAY.main_payment_method,
    R.review_score, R.review_comment
INTO olist_final_table
FROM clean_orders_table O
LEFT JOIN clean_customers_table C ON O.customer_id = C.customer_id
LEFT JOIN olist_order_items_dataset I ON O.order_id = I.order_id
LEFT JOIN clean_products_table P ON I.product_id = P.product_id
LEFT JOIN clean_sellers_table S ON I.seller_id = S.seller_id
LEFT JOIN clean_payments_table PAY ON O.order_id = PAY.order_id
LEFT JOIN clean_reviews_table R ON O.order_id = R.order_id;


SELECT TOP 100 * FROM olist_final_table;