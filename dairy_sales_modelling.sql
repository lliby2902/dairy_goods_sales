--view info--
SELECT TOP 10*
FROM [diary_sales].[dbo].[dairy_dataset];

--changing name--
EXEC sp_rename 'dbo.dairy_dataset.Location', 'f_location', 'COLUMN';
EXEC sp_rename 'dbo.dairy_dataset.Date', 'f_date', 'COLUMN';

--data profiling--
SELECT DISTINCT*
FROM [diary_sales].[dbo].[dairy_dataset];

SELECT
    MIN([f_date]),
    MAX([f_date])
FROM [diary_sales].[dbo].[dairy_dataset];

--changing data type--
ALTER TABLE [diary_sales].[dbo].[dairy_dataset]
ALTER COLUMN f_date DATE;

--checking null--
SELECT *
FROM [diary_sales].[dbo].[dairy_dataset]
WHERE [f_location] IS NULL
    OR [Total_Land_Area_acres] IS NULL
    OR [Number_of_Cows] IS NULL
    OR [Farm_Size] IS NULL
    OR [f_date] IS NULL
    OR [Product_ID] IS NULL
    OR [Product_Name] IS NULL
    OR [Brand] IS NULL
    OR [Quantity_liters_kg] IS NULL
    OR [Price_per_Unit] IS NULL
    OR [Total_Value] IS NULL
    OR [Shelf_Life_days] IS NULL
    OR [Storage_Condition] IS NULL
    OR [Production_Date] IS NULL
    OR [Expiration_Date] IS NULL
    OR [Quantity_Sold_liters_kg] IS NULL
    OR [Price_per_Unit_sold] IS NULL
    OR [Approx_Total_Revenue_INR] IS NULL
    OR [Customer_Location] IS NULL
    OR [Sales_Channel] IS NULL
    OR [Quantity_in_Stock_liters_kg] IS NULL
    OR [Minimum_Stock_Threshold_liters_kg] IS NULL
    OR [Reorder_Quantity_liters_kg] IS NULL;

WITH dup AS(
SELECT *,
    ROW_NUMBER() OVER(
        PARTITION BY f_date, f_location, Product_ID, Brand, Sales_Channel
        ORDER BY f_date
    ) as dup_check
FROM [diary_sales].[dbo].[dairy_dataset]
)
SELECT *
FROM dup
WHERE dup_check > 1;

WITH iqr AS(
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY [Price_per_Unit]) OVER() AS Q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY [Price_per_Unit]) OVER() AS Q3
    FROM [diary_sales].[dbo].[dairy_dataset]
)
SELECT [Price_per_Unit], Q1, Q3
FROM [diary_sales].[dbo].[dairy_dataset] AS d, iqr
WHERE [Price_per_Unit] > Q3 + 1.5*(Q3 - Q1)
    OR [Price_per_Unit] < Q1 - 1.5*(Q3 - Q1);

WITH z AS(
SELECT
    AVG(Total_Value) as a, STDEVP(Total_Value) as s
FROM [diary_sales].[dbo].[dairy_dataset]
)
SELECT d.*
FROM [diary_sales].[dbo].[dairy_dataset] as d, z
WHERE ABS((Total_value - a)/ s) > 3;

WITH dis_farm AS(
    SELECT DISTINCT
        f_location,
        total_land_area_acres,
        number_of_cows,
        farm_size
    FROM [diary_sales].[dbo].[dairy_dataset]
)
SELECT
    CONCAT(
        'FARM_',
        ROW_NUMBER() OVER(
            ORDER BY
                f_location,
                total_land_area_acres,
                number_of_cows,
                farm_size
        )
    ) AS farm_code,
    *
INTO stg_farm
FROM dis_farm;

WITH dis_prod AS(
    SELECT DISTINCT
        Product_ID,
        Product_Name,
        Brand,
        Shelf_Life_days,
        Storage_Condition
    FROM [diary_sales].[dbo].[dairy_dataset]
)
SELECT
    CONCAT(
        'PROD_',
        ROW_NUMBER() OVER(
            ORDER BY
                Product_ID,
                Product_Name,
                Brand,
                Shelf_Life_days,
                Storage_Condition
        )
    ) AS product_code,
    *
INTO stg_prod
FROM dis_prod;

SELECT
    r.*,
    f.farm_code,
    p.product_code
INTO stg_sales
FROM [diary_sales].[dbo].[dairy_dataset] r
JOIN stg_farm f
    ON r.f_location = f.f_location
   AND r.total_land_area_acres = f.total_land_area_acres
   AND r.number_of_cows = f.number_of_cows
   AND r.farm_size = f.farm_size
JOIN stg_prod p
    ON r.product_id = p.product_id
   AND r.product_name = p.product_name
   AND r.brand = p.Brand
   AND r.Shelf_Life_days = p.Shelf_Life_days
   AND r.storage_condition = p.storage_condition;

CREATE TABLE dim_date(
    date_key INT PRIMARY KEY,
    full_date DATE,
    day_no INT,
    month_no INT,
    quarter_no INT,
    year_no INT,
    day_name VARCHAR(20),
    month_name VARCHAR(20)
);
INSERT INTO dim_date(
    date_key,
    full_date,
    day_no,
    month_no,
    quarter_no,
    year_no,
    day_name,
    month_name
)
SELECT DISTINCT
    CAST(FORMAT(f_date, 'yyyyMMdd') AS INT) AS date_key,
    f_date,
    DAY(f_date),
    MONTH(f_date),
    DATEPART(QUARTER, f_date),
    YEAR(f_date),
    DATENAME(WEEKDAY,f_date),
    DATENAME(MONTH, f_date)
FROM stg_sales;

CREATE TABLE dim_product(
    product_key INT IDENTITY(1,1) PRIMARY KEY,
    product_code VARCHAR(100) UNIQUE,
    product_id VARCHAR(1000),
    product_name VARCHAR(100),
    brand VARCHAR(100),
    shelf_life INT,
    storage_condition VARCHAR(50) CHECK(
        storage_condition 
        IN('Ambient', 'Refrigerated', 'Polythene Packet', 'Frozen', 'Tetra Pack')
    ),
);
INSERT INTO dim_product(
    product_code,
    product_id,
    product_name,
    brand,
    shelf_life,
    storage_condition
)
SELECT DISTINCT
    [product_code],
    [Product_ID],
    [Product_Name],
    [Brand],
    [Shelf_Life_days],
    [Storage_Condition]
FROM stg_sales;

CREATE TABLE dim_farm(
    farm_key INT IDENTITY(1,1) PRIMARY KEY,
    farm_code VARCHAR(1000) UNIQUE,
    f_location VARCHAR(100),
    total_land_area DECIMAL(10, 2),
    no_cows INT,
    farm_size VARCHAR(50) CHECK(farm_size IN('Large', 'Medium', 'Small'))
);
INSERT INTO dim_farm(
    farm_code,
    f_location,
    total_land_area,
    no_cows,
    farm_size
)
SELECT DISTINCT
    farm_code,
    f_location,
    Total_Land_Area_acres,
    Number_of_Cows,
    Farm_Size
FROM stg_sales;

CREATE TABLE fact_sales(
    sales_key BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_key INT,
    farm_key INT,
    product_key INT,
    quantity_original DECIMAL(12,2),
    quantity_sold DECIMAL(12,2),
    quantity_in_stock DECIMAL(12,2),
    minimum_stock_threshold DECIMAL(12,2),
    reorder_point DECIMAL(12,2),
    price_original DECIMAL(12,2),
    price_sold DECIMAL(12,2),
    total_value DECIMAL(14,2),
    total_revenue DECIMAL(14,2),
    customer_location VARCHAR(100),
    sales_channel VARCHAR(50),
    production_date DATE,
    expiration_date DATE,
    CONSTRAINT fk_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    CONSTRAINT fk_farm
        FOREIGN KEY (farm_key) REFERENCES dim_farm(farm_key),
    CONSTRAINT fk_product
        FOREIGN KEY (product_key) REFERENCES dim_product(product_key)
);
INSERT INTO fact_sales(
    date_key,
    farm_key,
    product_key,
    quantity_original,
    quantity_sold,
    quantity_in_stock,
    minimum_stock_threshold,
    reorder_point,
    price_original,
    price_sold,
    total_value,
    total_revenue,
    customer_location,
    sales_channel,
    production_date,
    expiration_date
)
SELECT
    d.date_key,
    f.farm_key,
    p.product_key,
    s.[Quantity_liters_kg],
    s.[Quantity_Sold_liters_kg],
    s.[Quantity_in_Stock_liters_kg],
    s.[Minimum_Stock_Threshold_liters_kg],
    s.[Reorder_Quantity_liters_kg],
    s.[Price_per_Unit],
    s.[Price_per_Unit_sold],
    s.[Total_Value],
    s.[Approx_Total_Revenue_INR],
    s.[Customer_Location],
    s.[Sales_Channel],
    s.[Production_Date],
    s.[Expiration_Date]
FROM stg_sales s
JOIN dim_date d ON s.f_date = d.full_date
JOIN dim_farm f ON s.farm_code = f.farm_code
JOIN dim_product p ON s.product_code = p.product_code
