WITH orders AS (
    SELECT *
    FROM (VALUES
        (1001, 95, CAST('2021-01-01 10:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 10.45),
        (1001, 96, CAST('2021-01-01 15:00:00' AS TIMESTAMP), CAST('2021-01-10 10:00:00' AS TIMESTAMP), 'mobile', 9.64),
        (1002, 106, CAST('2021-01-03 05:00:00' AS TIMESTAMP), CAST('2021-01-07 15:00:00' AS TIMESTAMP), 'desktop', 10.45),
        (1002, 109, CAST('2021-01-03 15:00:00' AS TIMESTAMP), CAST('2021-01-11 15:00:00' AS TIMESTAMP), 'mobile', 10.27),
        (1001, 145, CAST('2021-01-05 10:00:00' AS TIMESTAMP), CAST('2021-01-06 10:00:00' AS TIMESTAMP), 'desktop', 22.55)
    ) AS t(user_id, order_id, paid_at, delivered_at, device_type, amount)
)

SELECT
	  user_id
	  -- Simple aggregations
    ,SUM(amount) AS amount_total
    ,COUNT(1) AS order_count
    ,MIN(delivered_at - paid_at) AS shortest_delivery
    ,MAX(delivered_at - paid_at) AS longest_delivery
    -- Distinct
    ,COUNT(DISTINCT CAST(paid_at AS DATE))  AS active_day_count
    ,approx_distinct(CAST(paid_at AS DATE)) AS active_day_count_approx
    -- Filters / piots
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
    ,COUNT_IF(device_type = 'mobile') AS mobile_order_count_shorter
    -- Sorted aggregations
    ,MIN_BY(
        amount,
        CAST(delivered_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS first_delivered_amount
    ,MAX_BY(
        device_type,
        CAST(paid_at AS VARCHAR) || lpad(CAST(order_id AS VARCHAR), 10, '0')
    ) AS last_payment_device
    -- With arrays
    ,array_agg(amount       ORDER BY delivered_at, order_id)[1]      AS first_delivered_amount_by_array
    ,array_agg(device_type  ORDER BY paid_at DESC, order_id DESC)[1] AS last_payment_device_by_array
    -- Combining sort & filter
  	,MIN_BY(
          amount,
          CASE WHEN device_type = 'desktop' THEN delivered_at ELSE NULL END
    ) AS first_desktop_delivered_amount
FROM orders
GROUP BY user_id
ORDER BY user_id
