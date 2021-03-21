WITH events_table AS (
  SELECT *
  FROM (VALUES
      (CAST('2021-01-01 09:12:12' AS DATETIME), 1, 'A1', 'pageView A')
      (CAST('2021-01-01 09:12:15' AS DATETIME), 1, 'A1', 'pageView B')
      (CAST('2021-01-01 09:13:13' AS DATETIME), 1, 'A1', 'Add product A')
      (CAST('2021-01-01 09:15:01' AS DATETIME), 1, 'A1', 'Add product B')
      (CAST('2021-01-01 16:35:14' AS DATETIME), 2, 'A2', 'pageView B')
      (CAST('2021-01-01 17:15:01' AS DATETIME), 2, 'A2', 'Add product B')
      (CAST('2021-01-01 20:23:15' AS DATETIME), 1, 'B1', 'Checkout')
      (CAST('2021-01-01 20:23:16' AS DATETIME), 1, NULL, 'Approved')
      (CAST('2021-01-01 20:25:44' AS DATETIME), 1, 'B1', 'Add product C')
      (CAST('2021-01-05 23:55:19' AS DATETIME), 2, 'B2', 'Add product B')
      (CAST('2021-01-06 00:01:21' AS DATETIME), 2, 'B2', 'Checkout')
      (CAST('2021-01-06 00:01:21' AS DATETIME), 2, NULL, 'Approved')
      (CAST('2021-01-06 00:05:19' AS DATETIME), 2, 'B2', 'Add product C')
      (CAST('2021-01-06 21:35:47' AS DATETIME), 2, 'A2', 'Checkout')
      (CAST('2021-01-06 21:25:37' AS DATETIME), 1, 'A3', 'Add product C')
      (CAST('2021-01-06 21:35:47' AS DATETIME), 1, 'A3', 'Checkout')
      (CAST('2021-01-06 21:33:48' AS DATETIME), 1, NULL, 'Approved')
      (CAST('2021-01-06 21:34:08' AS DATETIME), 1, 'A3', 'Add product D')
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
        event_type IN 'Approved'
        OR date_diff(
          LEAD(timestamp_utc, 1) OVER (PARTITION BY user_id ORDER BY timestamp_utc),
          timestamp_utc
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
    COALESCE(
      LEAD(session_end_indicator)
        OVER (PARTITION BY user_id ORDER BY timestamp_utc),
      0
    ) AS session_start_indicator
  FROM end_of_sessions
)

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
  user_session_id
  SUM(CASE WHEN event_type = 'Approved' THEN 1 ELSE 0 END) AS purchase_count
  SUM(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS checkout_attempts
  COUNT( DISTINCT CASE WHEN event_type LIKE 'pathView%' THEN event_type ELSE NULL END) AS distinct_pageviews_count
FROM
  sessions
GROUP BY
  user_id,
  user_session_id
