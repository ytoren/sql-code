[Back to my projects page](/)
[Back to Coding in SQL](/sql-code/)

# Aggregating data in SQL, or how to make counting even harder

They say that counting stuff is hard, especially when you want to count very different things at the same time. In this post I'll review a few methods for extracting aggregations simultaneously by combining simple counts sums and counts to more distinct, order-related aggregations.  Practically every aggregation discussed below can be achieved, on it's own, with much simpler queries (and I will show some examples below). If all you need is to extract a single number at a time you should definitely opt for simpler syntax. But the challenge I set in this post is to achieve all these sums & counts with in a single query - this is often more efficient and definitely simpler to write & maintain.   


### Raw data

To demonstrate how these methods work, let's generate some data: we are looking at the `orders` table in e-commerce our system, where each line contains user ID, order ID, time of payment, time of delivery, device used for making the order (we distinguish mobile from desktop) and the total amount paid in USD.

```sql
SELECT *
FROM (VALUES
    (1001, 95, CAST('2021-01-01 10:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 10.45),
    (1001, 96, CAST('2021-01-01 15:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 9.64),
    (1002, 106, CAST('2021-01-03 05:00:00' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'desktop', 10.45),
    (1002, 109, CAST('2021-01-03 15:00:00' AS TIMESTAMP), CAST('2021-01-11 15:00:00' AS TIMESTAMP), 'mobile', 10.27),
    (1001, 145, CAST('2021-01-05 10:00:00' AS TIMESTAMP), CAST('2021-01-06 10:00:00' AS TIMESTAMP), 'desktop', 22.55)
) AS t(user_id, order_id, paid_at, delivered_at, device_type, amount)
```

| user id | order id | paid at             | delivered at        | device type | amount |
|:--------|:---------|:--------------------|:--------------------|:------------|:-------|
| 1001    | 95       | 2021-01-01 10:00:00 | 2021-01-10 10:00:00 | mobile      | 10.45  |
| 1001    | 96       | 2021-01-01 15:00:00 | 2021-01-10 10:00:00 | mobile      | 9.64   |
| 1002    | 106      | 2021-01-03 05:00:00 | 2021-01-07 15:00:00 | desktop     | 10.45  |
| 1002    | 109      | 2021-01-03 15:00:00 | 2021-01-11 15:00:00 | mobile      | 10.27  |
| 1001    | 145      | 2021-01-05 10:00:00 | 2021-01-06 10:00:00 | desktop     | 22.55  |


## Simple sums & counts

We'll start with simple sums and counts. We want to know, per user, what was the total amount, how many line items and some stats about the delivery time (in days):

```sql
SELECT
    user_id
    ,SUM(amount) AS amount_total
    ,COUNT(1) AS order_count
    ,MIN(delivered_at - paid_at) AS shortest_delivery
    ,MAX(delivered_at - paid_at) AS longest_delivery
FROM orders
GROUP BY user_id
```

| user id | amount total | order count | shortest delivery | longest delivery |
|:--------|:-------------|:------------|:----------------- |:-----------------|
| 1001    | 42.64        | 3           | 1 00:00:00        | 9 00:00:00       |
| 1002    | 20.72        | 2           | 4 10:00:00        | 8 00:00:00       |

## COUNT DISTINCT

The next thing we want to find out is how many orders did each user make? In standard SQL we simply use `COUNT DISTINCT`, but this solution does not scale nicely. Depending on the size of the data and how accurate we have to be, we may want to use a faster approximation. Practically every implementation of SQL has it's own implementation of a faster-but-less-accurate `approx_distinct`, usually using the [HyperLogLog](https://en.wikipedia.org/wiki/HyperLogLog#HLL++) approximation. Just make sure to check your documentation so you understand the trade-offs (see [this example](https://database.guide/how-approx_count_distinct-works-in-sql-server/))

```sql
SELECT
    user_id
    ,COUNT(DISTINCT CAST(paid_at AS DATE))  AS active_day_count
    ,approx_distinct(CAST(paid_at AS DATE)) AS active_day_count_approx
FROM orders
GROUP BY user_id
```

| user id | active day count | active day count approx |
|:--------|:-----------------|:------------------------|
| 1001    | 2                | 2                       |
| 1002    | 1                | 1                       |


## Conditional aggregations & pivoting around

So far we used every row in our table for aggregation. But what if we only want to count some rows and not others? A straight forward approach would be to simply filter out the irrelevant rows, which is exactly what you should do if there is only one condition to filter by. For example, let's look at mobile orders:

```sql
SELECT
    user_id
    ,SUM(amount) AS total_amount_mobile
FROM orders
WHERE device_type = 'mobile'
GROUP BY user_id  
```

| user id | total amount mobile |
|:--------|:--------------------|
| 1001    | 20.09               |
| 1002    | 10.27               |

But what if there's more than one condition we want to use? We can create separate filtered queries for every single condition and JOIN the tables together on `user_id`, but this may not be very efficient, and definitely not fun to write and maintain. We can achieve the same result with a single query: for each filter we use a `CASE WHEN` statement that replaces the values we don't want to aggregate with either 0's or NULL values. This works not just for simple aggregations but also for distinct counts (accurate or approximate).

```sql
SELECT
    user_id
   ,COUNT(1) AS order_count
    ,SUM(
        CASE
            WHEN device_type = 'mobile'
            THEN 1
            ELSE 0
        END
    ) AS mobile_order_count
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
            THEN CAST(paid_at AS DATE)
            ELSE NULL
        END
    ) AS mobile_active_day_count
    ,SUM(
        CASE
            WHEN delivered_at - paid_at <= INTERVAL '1' day
            THEN 1
            ELSE 0
        END
    ) AS single_day_delivery
FROM orders
GROUP BY user_id
```

| user id | order count | mobile order count | mobile amount | mobile active day count | single day delivery |
|:--------|:------------|:-------------------|:--------------|:------------------------|---------------------|
| 1001    | 3           | 2                  | 20.09         | 1                       | 1                   |
| 1002    | 2           | 1                  | 10.27         | 1                       | 0                   |

Most SQL dialects will have some convenience functions to make the syntax shorter, but typically they will not be very flexible (for example many dialects will have `COUNT_IF(<filter>)`, which is equivalent to `SUM(CASE WHEN <filter> THEN 1 ELSE 0 END)`, but do not have `SUM_IF` or provisions for distinct counts.

```sql
SELECT
    user_id
    ,COUNT(1) AS order_count
    ,COUNT_IF(device_type = 'mobile') AS mobile_order_count
FROM orders
GROUP BY user_id
```

| user id | order count | mobile order count |
|:--------|:------------|:-------------------|
| 1001    | 3           | 2                  |
| 1002    | 2           | 1                  |


By the way, we can use the same mechanism to pivot the data by hard-coding specific values (especially if our SQL dialect does not have the `PIVOT` functionality). Pretty ugly, but works:

```sql
SELECT
    user_id
    ,COUNT_IF(device_type = 'mobile')  AS device_mobile
    ,COUNT_IF(device_type = 'desktop') AS device_desktop
FROM orders
GROUP BY user_id
```

| user id | device mobile | device desktop |
|:--------|:--------------|:---------------|
| 1001    | 2             | 1              |
| 1002    | 1             | 1              |


## Order aggregations, with a single sorting order

Now let's make counting even harder: What if we are not interested just "overall" aggregations (like sum/count/min/max/...) but in aggregations that depend on the order of the data? A good example for our case would be "first order amount" or "last delivery date from a mobile device".


### Finding first / last values with pre-sorting

As long as we order data using a single "index", we can simplify things by pre-sorting the data. This will allow us to use aggregation functions like `FIRST` or `LAST` or `NTH` aggregation functions which exist in some dialects (although not in Presto, which is what I'm using to test these queries). Typically, these functions do not ensure order on their own but rely on either explicit pre-sorting of the data or have some kind of `ORDER BY` clause to guarantee "tie-braking" - they will return a single line even if multiple lines have the same sorting index (no guarantee which line though...)

```sql
WITH sorted_orders AS (
    SELECT *
    FROM orders
    ORDER BY user_id, paid_at, order_id
)

SELECT
    user_id
    ,FIRST(amount)        AS first_order_amount  
    ,LAST(device_type)    AS last_order_device
FROM sorted_orders
GROUP BY user_id
```

| user id | first order amount | last order device |
|:--------|:-------------------|:------------------|
| 1001    | 10.45              | desktop           |
| 1002    | 10.45              | mobile            |


### Finding first / last values with convenience functions

Some SQL dialects will have convenience functions that will do the pre-sorting for you. For example the [presto syntax](https://prestodb.io/docs/current/functions/aggregate.html#id3) makes things short and clear in my opinion. These functions will return a single line, but typically only accept a single column for sorting. If we need to sort by multiple columns we either have to generate a sorting column or use a concatenated expression. In our example, orders can by paid at the same time, so we add `order_id` to the sorting expression (lower ID's are created earlier)

```sql
SELECT
    user_id
    ,MIN_BY(
        amount,
		CAST(paid_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS first_order_amount
    ,MAX_BY(
        device_type,
        CAST(paid_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS last_delieverd_device   
FROM orders
GROUP BY user_id
```


## Order aggregations, with completely different sorting

### Convenience functions

If you're very lucky, your SQL dialect will allow you to use different sorting expressions in a single query inside the convenience function.

```sql
SELECT
    user_id
    ,MIN_BY(
        amount,
        CAST(delivered_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS first_delivered_amount   
    ,MAX_BY(
        device_type,
        CAST(paid_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS last_payment_device
FROM orders
GROUP BY user_id
```

| user id | first delivered amount | last payment device |
|:--------|:-----------------------|:--------------------|
| 1001    | 22.55                  | desktop             |
| 1002    | 10.45                  | mobile              |


### Array syntax

If you're slightly less lucky (but still lucky enough), your SQL dialect will allow sorting inside arrays. You'll have to use separate array aggregations, but the sorting expression syntax is usually nicer. They "trick" is to sort in a way that will always place the number you need at the top of the array (so you don't need to know the array's length in advance).

```sql
SELECT
    user_id
    ,array_agg(amount       ORDER BY delivered_at, order_id)[1]      AS first_delivered_amount
    ,array_agg(device_type  ORDER BY paid_at DESC, order_id DESC)[1] AS last_payment_device  
FROM orders
GROUP BY user_id
```

There are some problems with array syntax:

- The value of the first cell in arrays changes from dialect to dialect. For example, in SparkSQL arrays start at `[0]` while in Presto they start at `[1]`
- Relying on absolute positions is a source for a lot of confusion and bugs...
- It's definitely less clear and readable that the convenience function syntax


### Order aggregations using window functions

And if you're very unlucky... You'll have to use a different strategy. Practically all SQL dialects support window functions, and most of them allow different window expressions in the same query (which allows sorting the data by more than one order).

We break down the process to 3 stages to make things a bit more readable (isn't aliasing great?)

1. Add sorting expressions `sort_by_paid` and `sort_by_delivered`. This is just to make the code a bit more readable.
2. For each user, replicate the first value of `sort_by_paid` and the last value of `sort_by_delivered`.
3. When we do the aggregation we use a `CASE WHEN` statement. This way we keep only one row per user, and therefore we can use the `ARBITRARY` aggregation function (although `MIN` or `MAX` would work here too).

```sql
WITH orders_with_sorting AS (
    -- Stage 1
    SELECT
        *
        ,CAST(delivered_at AS VARCHAR)  || lpad(CAST(order_id AS VARCHAR), 10, '0') AS sort_by_delivered
        ,CAST(paid_at AS VARCHAR)       || lpad(CAST(order_id AS VARCHAR), 10, '0') AS sort_by_paid
    FROM orders
)

,orders_with_pointers AS (
    -- Stage 2
    SELECT
        *
        ,MIN(sort_by_delivered) OVER (PARTITION BY user_id) AS first_delivered_pointer
        ,MAX(sort_by_paid)      OVER (PARTITION BY user_id) AS last_paid_pointer
    FROM orders_with_sorting
)

-- Stage 3
SELECT
    user_id
    ,ARBITRARY(
        CASE
            WHEN sort_by_delivered = first_delivered_pointer
            THEN amount
            ELSE NULL
        END
    ) AS first_delivered_amount
    ,ARBITRARY(
        CASE
            WHEN sort_by_paid = last_paid_pointer
            THEN device_type
            ELSE NULL
        END
    ) AS last_payment_device
FROM orders_with_pointers
GROUP BY user_id
```


### Combining multiple sorting orders and filters

For example finding the very first order amount by pay date, vs. finding the first amount of an order made from a mobile device:

```sql
SELECT
	user_id
	,MIN_BY(device_type, paid_at) AS first_payment_device
	,MIN_BY(
        amount,
        CASE WHEN device_type = 'desktop' THEN delivered_at ELSE NULL END
    ) AS first_desktop_delivered_amount
FROM orders
GROUP BY user_id
ORDER BY user_id
```

| user id | first payment device | first desktop delivered amount |
|:--------|:---------------------|:-------------------------------|
| 1001    | mobile               | 22.55                          |
| 1002    | desktop              | 10.45                          |


### Getting more than one value at a time (shortcuts)
TBD


## Full SQL code

You can find the full code in [this file](https://github.com/ytoren/sql-code/blob/main/aggregation_types.sql)

<!--
```sql
SELECT
    user_id
    ,map_agg(paid_at, device_type) AS map_by_paid
    ,map_agg(delivered_at, device_type) AS map_by_delivered
FROM orders
GROUP BY user_id
```
-->

<!--
### Finding multiple values with less code (but only if they have the same type)

What if we want to find a long list of values about the first order item and aggregate them to the user level? We can repeat the `MIN_BY` function again and again, which means a lot of repeated code (and potential for errors, especially when the sorting expression gets complicated). It's a bit of an edge-case, but if all the values we want to look-up are of the same type then we can save a lot of duplication.


We'll go back to simplified sorting expressions for this example. This is duplicated code:

```sql
SELECT
    user_id
    ,MIN_BY(amount, paid_at)        AS first_order_amount
    ,MIN_BY(device_type, paid_at)   AS first_order_device
    ,MIN_BY(delivered_at, paid_at)  AS first_order_delivered_at
	...
FROM orders
GROUP BY user_id
```


#### Avoiding repetition with arrays / maps

```sql
WITH first_values AS (
	SELECT
	    user_id
	    ,MIN_BY(ARRAY [order_id, amount, ...], paid_at) AS first_order_array
        -- In some dialects: ARRAY(order_id, product_id, ...)
	FROM orders
	GROUP BY user_id
)

SELECT
	user_id
	,first_order_array[0] AS first_order_id
	,first_order_array[1] AS first_order_amount
    ...
FROM first_values
```

There are several downsides for using arrays:

- The value of the first cell in arrays changes from dialect to dialect. For example, in SparkSQL arrays start at `[0]` while in Presto they start at `[1]`
- Relying on absolute positions is a source for a lot of confusion and bugs...

So instead I recommend using maps (key / value pairs), which support call by name. The idea is to extract all the values into a map in one go, and extract the values from the map column only when necessary. Again we use Presto syntax:

```sql
WITH first_values AS (
	SELECT
	    user_id
	    ,MIN_BY(
            MAP_FROM_ENTRIES(
                ARRAY ['delivered_at', 'paid_at', 'device_type'],
                ARRAY [delivered_at, paid_at, device_type]
            ),
            -- In some dialects: MAP('delivered_at', delivered_at, 'paid_at', paid_at, 'device_type', device_type)
            paid_at
        ) AS first_order_map
	FROM orders
	GROUP BY user_id
)

SELECT
	user_id
	,date_diff(
        'day',
        first_order_map['paid_at'],
        first_order_map['delivered_at']
    ) AS first_order_delivery_days
	,first_order_map['device_type'] AS first_order_device_type
FROM first_values
```

As you can see this syntax takes us away from the very readable SQL syntax, but is much easier to maintain and debug (especially if we want to extract a lot of values in a single query)

-->
