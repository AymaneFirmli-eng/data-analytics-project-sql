-- =============================================================
-- Create Database and Schemas (PostgreSQL Version)
-- =============================================================

-- Step 1: Drop and recreate the 'DataWarehouseAnalytics' database
-- (Run this while connected to the 'postgres' database)

/* THIS PORTION BELLOW DECONNECTS ANY USER FROM THE DATABASE CNX IF THERE IS ONE (optional to run)*/

/*
 
 
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'datawarehouseanalytics' 
  AND pid <> pg_backend_pid();

*/

DROP DATABASE IF EXISTS datawarehouse_analytics;

CREATE DATABASE datawarehouse_analytics;


-- NOTE: After running the above block, reconnect DBeaver to the new 'DataWarehouseAnalytics' in the top thingy, then run the rest below:

-- Step 2: Create Schema and Tables
CREATE SCHEMA IF NOT EXISTS gold;

DROP TABLE IF EXISTS gold.dim_customers;
CREATE TABLE gold.dim_customers(
    customer_key int,
    customer_id int,
    customer_number varchar(50),
    first_name varchar(50),
    last_name varchar(50),
    country varchar(50),
    marital_status varchar(50),
    gender varchar(50),
    birthdate date,
    create_date date
);

DROP TABLE IF EXISTS gold.dim_products;
CREATE TABLE gold.dim_products(
    product_key int,
    product_id int,
    product_number varchar(50),
    product_name varchar(50),
    category_id varchar(50),
    category varchar(50),
    subcategory varchar(50),
    maintenance varchar(50),
    cost int,
    product_line varchar(50),
    start_date date 
);

DROP TABLE IF EXISTS gold.fact_sales;
CREATE TABLE gold.fact_sales(
    order_number varchar(50),
    product_key int,
    customer_key int,
    order_date date,
    shipping_date date,
    due_date date,
    sales_amount int,
    quantity smallint,
    price int 
);

-- Step 3: Load Data using COPY 
-- (Make sure to update the file paths to absolute paths)

-- We're making full loads 
-- With the thr trucate and copy from the cvs files to be seen in the github repo 
TRUNCATE TABLE gold.dim_customers;

COPY gold.dim_customers
FROM '/Users/macairm1/Desktop/*DATA_ENG_PROJECTS/ongoing/sql-data-analytics-project/datasets/flat-files/dim_customers.csv'
WITH (
FORMAT csv,
HEADER true,
DELIMITER ',');

TRUNCATE TABLE gold.dim_products;

COPY gold.dim_products
FROM '/Users/macairm1/Desktop/*DATA_ENG_PROJECTS/ongoing/sql-data-analytics-project/datasets/flat-files/dim_products.csv'
WITH (FORMAT csv, 
HEADER true ,
DELIMITER ',');

TRUNCATE TABLE gold.fact_sales;

COPY gold.fact_sales
FROM '/Users/macairm1/Desktop/*DATA_ENG_PROJECTS/ongoing/sql-data-analytics-project/datasets/flat-files/fact_sales.csv'
WITH (FORMAT csv,
HEADER true,
DELIMITER ',');
