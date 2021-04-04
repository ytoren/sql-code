WITH orders AS (
  SELECT *
  FROM (VALUES
      (1001, 95, 11, 1, CAST('2021-01-01 09:12:12' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 10.45),
      (1001, 95, 12, 2, CAST('2021-01-01 09:12:12' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 9.64),
      (1001, 135, 13, 1, CAST('2021-01-05 15:23:23' AS TIMESTAMP), CAST('2021-01-06 10:00:00' AS TIMESTAMP), 'desktop', 22.55),
      (1001, 135, 14, 2, CAST('2021-01-05 15:23:23' AS TIMESTAMP), CAST('2021-01-11 15:00:00' AS TIMESTAMP), 'desktop', 10.27),
      (1002, 145, 11, 1, CAST('2021-01-02 03:27:27' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'mobile', 10.45),
      (1002, 145, 14, 2, CAST('2021-01-02 03:27:27' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'mobile', 10.27)
  ) AS t(user_id, order_id, product_id, order_line, paid_at, delivered_at, device_type, amount)
)

SELECT
    user_id
    /* simple aggregations */
    ,SUM(amount) AS amount_total
    ,COUNT(1) AS line_item_count
    ,MIN(delivered_at - paid_at) AS shortest_delivery
    ,MAX(delivered_at - paid_at) AS longest_delivery
    /* distinct */
    ,COUNT(DISTINCT order_id) AS order_count
    ,approx_distinct(order_id) AS order_count_approx
    /* conditional aggregation */
    ,SUM(
        CASE
            WHEN device_type = 'mobile'
            THEN 1
            ELSE 0
        END
    ) AS mobile_line_item_count
    ,COUNT_IF(device_type = 'mobile') AS mobile_line_item_count_shorter
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
    /* pivot */
    ,COUNT_IF(product_id = 11) AS product_11
	,COUNT_IF(product_id = 12) AS product_12
	,COUNT_IF(product_id = 13) AS product_13
	,COUNT_IF(product_id = 14) AS product_14
	,MIN_BY(amount, paid_at) AS first_item_amount
    ,MAX_BY(device_type, paid_at) AS last_device
FROM orders
GROUP BY user_id 
