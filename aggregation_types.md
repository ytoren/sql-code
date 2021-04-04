# Aggregating data in SQL, or how to make counting even harder

They say that counting stuff is hard, especially when you want to count very different things at the same time. In this post I'll review a few methods for extracting aggregations simultaneously by combining simple counts sums and counts to more distinct, order-related aggregations.  Practically every aggregation discussed below can be achieved, on it's own, with much simpler queries (and I will show some examples below). If all you need is to extract a single number at a time you should definitely opt for simpler syntax. But the challenge I set in this post is to achieve all these sums & counts with in a single query - this is often more efficient and definitely simpler to write & maintain.   

To demonstrate how these methods work, let's generate some data: we are looking at the `orders` table in e-commerce our system, where each line contains user ID, order ID, product ID, order line number, time of payment, time of delivery, device used for making the order (we distinguish mobile from desktop) and the amount paid in USD.

### Raw data

```sql
SELECT *
FROM (VALUES
    (1001, 95, 11, 1, CAST('2021-01-01 10:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 10.45),
    (1001, 95, 12, 2, CAST('2021-01-01 10:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 9.64),
    (1001, 135, 13, 1, CAST('2021-01-05 15:00:00' AS TIMESTAMP), CAST('2021-01-06 10:00:00' AS TIMESTAMP), 'desktop', 22.55),
    (1001, 135, 14, 2, CAST('2021-01-05 15:00:00' AS TIMESTAMP), CAST('2021-01-11 15:00:00' AS TIMESTAMP), 'desktop', 10.27),
    (1002, 145, 11, 1, CAST('2021-01-02 05:00:00' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'mobile', 10.45),
    (1002, 145, 14, 2, CAST('2021-01-02 05:00:00' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'mobile', 10.27)
) AS t(user_id, order_id, product_id, order_line, paid_at, delivered_at, device_type, amount)
```

| user id | order id | product id | order line | paid at             | delivered at        | device type | amount |
|:--------|:---------|:-----------|:-----------|:--------------------|:--------------------|:------------|:-------|
| 1001    | 95       | 11         | 1          | 2021-01-01 10:00:00 | 2021-01-10 10:00:00 | mobile      | 10.45  |
| 1001    | 95       | 12         | 2          | 2021-01-01 10:00:00 | 2021-01-10 10:00:00 | mobile      | 9.64   |
| 1001    | 135      | 13         | 1          | 2021-01-05 15:00:00 | 2021-01-06 10:00:00 | desktop     | 22.55  |
| 1001    | 135      | 14         | 2          | 2021-01-05 15:00:00 | 2021-01-11 15:00:00 | desktop     | 10.27  |
| 1002    | 145      | 11         | 1          | 2021-01-02 05:00:00 | 2021-01-07 15:00:00 | mobile      | 10.45  |


## Simple sums & counts

We'll start with simple sums and counts. We want to know, per user, what was the total amount, how many line items and some stats about the delivery time (in days):

```sql
SELECT
    user_id
    ,SUM(amount) AS amount_total
    ,COUNT(1) AS line_item_count
    ,MIN(delivered_at - paid_at) AS shortest_delivery
    ,MAX(delivered_at - paid_at) AS longest_delivery
FROM orders
GROUP BY user_id
```

| user id | amount total | line item count | shortest delivery | longest delivery |
|:--------|:-------------|:----------------|:----------------- |:-----------------|
| 1001    | 52.91        | 4               | 0.79              | 10               |
| 1002    | 10.45        | 1               | 5.17              | 5.17             |


## COUNT DISTINCT

The next thing we want to find out is how many orders did each user make? In standard SQL we simply use `COUNT DISTINCT`, but this solution does not scale nicely. Depending on the size of the data and how accurate we have to be, we may want to use a faster approximation. Practically every implementation of SQL has it's own implementation of a faster-but-less-accurate `approx_distinct`, usually using the [HyperLogLog](https://en.wikipedia.org/wiki/HyperLogLog#HLL++) approximation. Just make sure to check your documentation so you understand the trade-offs (see [this example](https://database.guide/how-approx_count_distinct-works-in-sql-server/))

```sql
SELECT
    user_id
    ,COUNT(1) AS line_item_count
    ,COUNT(DISTINCT order_id) AS order_count
    ,approx_distinct(order_id) AS order_count_approx
FROM orders
GROUP BY user_id
```

| user id | line item count | order count | order count approx |
|:--------|:----------------|:------------|:-------------------|
| 1001    | 4               | 2           | 2                  |
| 1002    | 1               | 1           | 1                  |


## Conditional aggregations & pivoting around

So far we used every row in our table for aggregation. But what if we only want to count some rows and not others? A straight forward approach would be to simply filter out the irrelevant rows, which is exactly what you should do if there is only one condition to filter by. For example, let's look at mobile orders:

```sql
SELECT
	user_id
	,SUM(amount) AS total_amount_mobile
FROM orders
WHERE device_type = 'mobile'  
```

| user id | total amount mobile |
|:--------|:--------------------|
| 1001    | 20.09               |
| 1002    | 10.45               |

But what if there's more than one condition we want to use? We can create separate filtered queries for every single condition and JOIN the tables together on `user_id`, but this may not be very efficient, and definitely not fun to write and maintain. We can achieve the same result with a single query: for each filter we use a `CASE WHEN` statement that replaces the values we don't want to aggregate with either 0's or NULL values. This works not just for simple aggregations but also for distinct counts (accurate or approximate).

```sql
SELECT
    user_id
   ,COUNT(1) AS line_item_count
    ,SUM(
        CASE
            WHEN device_type = 'mobile'
            THEN 1
            ELSE 0
        END
    ) AS mobile_line_item_count
    ,SUM(
        CASE
            WHEN device_type = 'mobile'
            THEN amount
            ELSE 0
        END
    ) AS mobile_amount
    ,APPROX_DISTINCT(
        CASE
            WHEN device_type = 'mobile'
            THEN order_id
            ELSE NULL
        END
    ) AS mobile_order_count
    ,SUM(
    	CASE
    		WHEN delivered_at - paid_at < 1
    		THEN 1
    		ELSE 0
    	END
    ) AS single_day_delivery
FROM orders
GROUP BY user_id
```

| user id | line item count | mobile line item count | mobile amount | mobile order count | single day delivery |
|:--------|:----------------|:-----------------------|:--------------|:-------------------|---------------------|
| 1001    | 4               | 2                      | 20.09         | 1                  | 1                   |
| 1002    | 1               | 1                      | 10.45         | 1                  | 0                   |


Most SQL dialects will have some convenience functions to make the syntax shorter, but typically they will not be very flexible (for example many dialects will have `COUNT_IF(<filter>)`, which is equivalent to `SUM(CASE WHEN <filter> THEN 1 ELSE 0 END)`, but do not have `SUM_IF` or provisions for distinct counts.

```sql
SELECT
	user_id
	,COUNT(1) AS line_item_count
    ,COUNT_IF(device_type = 'mobile') AS mobile_line_items
FROM orders
GROUP BY user_id
```

| user id | line item count | mobile line items |
|:--------|:----------------|:------------------|
| 1001    | 4               | 2                 |
| 1002    | 1               | 1                 |


By the way, we can use the same mechanism to pivot the data by hard-coding specific values (especially if our SQL dialect does not have the `PIVOT` functionality). Pretty ugly, but works:

```sql
SELECT
	user_id
	,COUNT_IF(product_id = 11) AS product_11
	,COUNT_IF(product_id = 12) AS product_12
	,COUNT_IF(product_id = 13) AS product_13
	,COUNT_IF(product_id = 14) AS product_14
FROM orders
GROUP BY user_id
```

| user id | product 11 | product 12 | product 13 | product 14 |
|:--------|:-----------|:-----------|:-----------|:-----------|
| 1001    | 1          | 1          | 1          | 1          |
| 1002    | 1          | 0          | 0          | 0          |


## Order aggregations, with a single sorting order

Now let's make counting even harder: What if we are not interested just "overall" aggregations (like sum/count/min/max/...) but in aggregations that depend on the order of the data? A good example for our case would be "first order amount" or "last delivery date from a mobile device".

### Pre-sorting

As long as we order data using a single "index", we can simplify things by pre-sorting the data. This will allow us to use aggregation functions like `FIRST` or `LAST` or `NTH` aggregation functions (or in some dialects `first_value`, `last_value`, `nth_value`). Usually, you will find these functions used as part of a window function clause. In some dialects you can use them as aggregation functions, however they do not ensure order on their own. Instead they rely on explicit pre-sorting of the data.  

```sql
WITH sorted_orders AS (
    SELECT *
    FROM ordres
    ORDER BY user_id, paid_at, order_line
)

SELECT
    user_id
    ,FIRST(amount) AS first_item_amount
    ,LAST(device_type) AS last_device
FROM sorted_orders
```

Note that since we have multiple order-lines at the same time, we added the line number to the sort to ensure the first added product is first. But in any case these functions guarantee "tie-braking" - they will return a single line even if multiple lies have the same sorting index (but there's no guarantee which line though...)

| user id | first item amount | last device  |
|:--------|:------------------|:-------------|
| 1001    | 10.45             | desktop      |
| 1002    | 10.45             | mobile       |


### Custom functions

Some SQL dialects will have convenience functions that will do the pre-sorting for you. For example the [presto syntax](https://prestodb.io/docs/current/functions/aggregate.html#id3) makes things short and clear in my opinion:
```sql
SELECT
    user_id
    ,MIN_BY(amount, paid_at) AS first_item_amount
    ,MAX_BY(device_type, paid_at) AS last_device   
FROM orders
GROUP BY user_id
```

The issue is that most of these convenience functions will only allow one sorting. What if we want to find both the last device used for ordering and the last product delivered?

## Order matters, with more than one sorting

TBD
<!-- What if we want to sort by different things? For example first paid order and last delivered order?

### Window functions

replicate the value and the use a filter. works only if there are no ties...


### Arrays and maps

The issue is that many SQL implementation will allow only one of these clauses per statement (this is because essentially they sort the data in the background and do this only once).

```sql
SELECT
    user_id
    ,map_agg(paid_at, device_type) AS map_by_paid
    ,map_agg(delivered_at, device_type) AS map_by_delivered
FROM orders
GROUP BY user_id
```
-->
