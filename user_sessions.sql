WITH events_table AS (
  SELECT *
  FROM (VALUES
    (CAST('2021-01-01 09:12:12' AS TIMESTAMP), 'uid001', 'A1', 'pageView A'),
    (CAST('2021-01-01 09:12:15' AS TIMESTAMP), 'uid001', 'A1', 'pageView B'),
    (CAST('2021-01-01 09:13:13' AS TIMESTAMP), 'uid001', 'A1', 'Add product A'),
    (CAST('2021-01-01 09:15:01' AS TIMESTAMP), 'uid001', 'A1', 'Add product B'),
    (CAST('2021-01-01 16:35:14' AS TIMESTAMP), 'uid002', 'A2', 'pageView B'),
    (CAST('2021-01-01 17:15:01' AS TIMESTAMP), 'uid002', 'A2', 'Add product B'),
    (CAST('2021-01-01 20:23:15' AS TIMESTAMP), 'uid001', 'B1', 'Checkout'),
    (CAST('2021-01-01 20:23:16' AS TIMESTAMP), 'uid001', NULL, 'Approved'),
    (CAST('2021-01-01 20:25:44' AS TIMESTAMP), 'uid001', 'B1', 'Add product C'),
    (CAST('2021-01-05 23:55:19' AS TIMESTAMP), 'uid002', 'B2', 'Add product B'),
    (CAST('2021-01-06 00:01:21' AS TIMESTAMP), 'uid002', 'B2', 'Checkout'),
    (CAST('2021-01-06 00:01:21' AS TIMESTAMP), 'uid002', NULL, 'Approved'),
    (CAST('2021-01-06 00:05:19' AS TIMESTAMP), 'uid002', 'B2', 'Add product C'),
    (CAST('2021-01-06 21:35:47' AS TIMESTAMP), 'uid002', 'A2', 'Checkout'),
    (CAST('2021-01-06 21:25:37' AS TIMESTAMP), 'uid001', 'A3', 'Add product C'),
    (CAST('2021-01-06 21:35:47' AS TIMESTAMP), 'uid001', 'A3', 'Checkout'),
    (CAST('2021-01-06 21:33:48' AS TIMESTAMP), 'uid001', NULL, 'Approved'),
    (CAST('2021-01-06 21:34:08' AS TIMESTAMP), 'uid001', 'A3', 'pageView D')
  ) AS t(timestamp_utc, user_id, token, event_type)
),

end_of_sessions AS (
  SELECT
    timestamp_utc,
    user_id,
    event_type,
    token,
    CASE
      WHEN
        event_type = 'Approved'
        OR date_diff(
          'day',
          timestamp_utc,
          COALESCE(LEAD(timestamp_utc, 1) OVER (PARTITION BY user_id ORDER BY timestamp_utc), CURRENT_TIMESTAMP)
        ) >= 4
      THEN 1
      ELSE 0
    END AS session_end_indicator
  FROM events_table
),

start_of_sessions AS (
  SELECT
    timestamp_utc,
    user_id,
    event_type,
    token,
    session_end_indicator,
    COALESCE(
      LAG(session_end_indicator, 1)
        OVER (PARTITION BY user_id ORDER BY timestamp_utc),
      0
    ) AS session_start_indicator
  FROM end_of_sessions
),

user_sessions AS (
  SELECT
    timestamp_utc,
    user_id,
    event_type,
    token,
    SUM(session_start_indicator)
      OVER (PARTITION BY user_id ORDER BY timestamp_utc ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    AS user_session_id
  FROM start_of_sessions
)

SELECT
  user_id,
  user_session_id,
  SUM(CASE WHEN event_type = 'Approved' THEN 1 ELSE 0 END) AS purchase_count,
  SUM(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS checkout_attempts,
  COUNT(DISTINCT CASE WHEN event_type LIKE 'pageView%' THEN event_type ELSE NULL END) AS distinct_pageviews_count
FROM
  user_sessions
GROUP BY
  user_id,
  user_session_id
ORDER BY
  user_id,
  user_session_id
