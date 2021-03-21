# What's in a session

Good news! Your engineers finally got around to implementing pageView tracking and maybe some custom events (buttons clicked, backend events etc),
which means it's time to start figuring out what your users are *actually* doing with your product. And while counting tokens & clicks is great place to start, you also want to put things in context - aka "the session".

A session is a much (ab)used term and
some tracking tools come with their own baked-in definition
30 minute timeout
4-day the cart expires on the backend (but we haven't implemented these events yet)

Some events are "absolute" indicators of session end. Other cases require date differences (but date change by itself does not necessarily means a new session)

Which means that aggregating event / ledger data into meaningful sessions is an exercise in fencing - not the sword kind but the kind that makes good neighbours.


- User 1 started on a browser with 2 open tabs, added 2 products (A/B), and then completed the activity on a tablet app that evening.
- The same user also added a product to cart immediately after checkout, but resumed shopping 5 days later (so the cart expired in between)
- User 2 added one product B to the cart and a few days later tried again (the cart expired) . The tracking cookie expired in between the events
- Our backend event that track approval of a checkout do not have the token, only the user ID.


```
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
```

The event ledger (rows come in by timestamp) looks like this:

```
SELECT * FROM events_table
```

| timestamp_utc       | user_id | token | event_type    |
|:--------------------|:--------|:------|:--------------|
| 2021-01-01 09:12:12 | 1       | A1    | pageView A    |
| 2021-01-01 09:12:15 | 1       | A1    | pageView B    |
| 2021-01-01 09:13:13 | 1       | A1    | Add product A |
| 2021-01-01 09:15:01 | 1       | A1    | Add product B |
| 2021-01-01 16:35:14 | 2       | A2    | pageView B    |
| 2021-01-01 17:15:01 | 2       | A2    | Add product B |
| 2021-01-01 20:23:15 | 1       | B1    | Checkout      |
| 2021-01-01 20:23:16 | 1       |       | Approved      |
| 2021-01-01 20:25:44 | 1       | B1    | Add product C |
| 2021-01-05 23:55:19 | 2       | B2    | Add product B |
| 2021-01-06 00:01:21 | 2       | B2    | Checkout      |
| 2021-01-06 00:01:21 | 2       |       | Approved      |
| 2021-01-06 00:05:19 | 2       | B2    | Add product C |
| 2021-01-06 21:35:47 | 2       | A2    | Checkout      |
| 2021-01-06 21:25:37 | 1       | A3    | Add product C |
| 2021-01-06 21:35:47 | 1       | A3    | Checkout      |
| 2021-01-06 21:33:48 | 1       |       | Approved      |
| 2021-01-06 21:34:08 | 1       | A3    | Add product D |


There's no need to actually sort the data by user & date, but it would help our visualization:

```
SELECT * FROM events_table ORDER BY user_id, timestamp_utc
```

| timestamp_utc       | user_id | token | event_type    |
|:--------------------|:--------|:------|:--------------|
| 2021-01-01 09:12:12 | 1       | A1    | pageView A    |
| 2021-01-01 09:12:15 | 1       | A1    | pageView B    |
| 2021-01-01 09:13:13 | 1       | A1    | Add product A |
| 2021-01-01 09:15:01 | 1       | A1    | Add product B |
| 2021-01-01 20:23:15 | 1       | B1    | Checkout      |
| 2021-01-01 20:23:16 | 1       |       | Approved      |
| 2021-01-01 20:25:44 | 1       | B1    | Add product C |
| 2021-01-06 21:25:37 | 1       | A3    | Add product C |
| 2021-01-06 21:35:47 | 1       | A3    | Checkout      |
| 2021-01-06 21:33:48 | 1       |       | Approved      |
| 2021-01-06 21:34:08 | 1       | A3    | Add product D |
| 2021-01-01 16:35:14 | 2       | A2    | pageView B    |
| 2021-01-01 17:15:01 | 2       | A2    | Add product B |
| 2021-01-05 23:55:19 | 2       | B2    | Add product B |
| 2021-01-06 00:01:21 | 2       | B2    | Checkout      |
| 2021-01-06 00:01:21 | 2       |       | Approved      |
| 2021-01-06 00:05:19 | 2       | B2    | Add product C |
| 2021-01-06 21:35:47 | 2       | A2    | Checkout      |



Rather than defining when a session starts it is easier to define when a session ends. This happens when a checkout is complete or

```
SELECT
  timestamp_utc,
  user_id,
  event_type,
  token,
  CASE
    WHEN
      event_type IN 'Approved'
      OR date_diff(
        LEAD(timestamp_utc, 1)
          OVER (PARTITION BY user_id ORDER BY timestamp_utc),
        timestamp_utc
      ) >= 4
    THEN 1
    ELSE 0
  END AS session_end_indicator
FROM events_table
```

| timestamp_utc       | user_id | token | event_type    | session_end_indicator |
|:--------------------|:--------|:------|:--------------|:----------------------|
| 2021-01-01 09:12:12 | 1       | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | 1       | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | 1       | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | 1       | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | 1       | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | 1       |       | Approved      | 1                     |
| 2021-01-01 20:25:44 | 1       | B1    | Add product C | 0                     |
| 2021-01-06 21:25:37 | 1       | A3    | Add product C | 0                     |
| 2021-01-06 21:35:47 | 1       | A3    | Checkout      | 0                     |
| 2021-01-06 21:33:48 | 1       |       | Approved      | 1                     |
| 2021-01-06 21:34:08 | 1       | A3    | Add product D | 0                     |
| 2021-01-01 16:35:14 | 2       | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | 2       | A2    | Add product B | 1                     |
| 2021-01-05 23:55:19 | 2       | B2    | Add product B | 0                     |
| 2021-01-06 00:01:21 | 2       | B2    | Checkout      | 0                     |
| 2021-01-06 00:01:21 | 2       |       | Approved      | 1                     |
| 2021-01-06 00:05:19 | 2       | B2    | Add product C | 0                     |
| 2021-01-06 21:35:47 | 2       | A2    | Checkout      | 0                     |


We then move the "end of session" market a step forward so we get a "start of next session" indicator

```
WITH end_of_sessions AS (
  SELECT
    timestamp_utc,
    user_id,
    event_type,
    token,    
    CASE
      WHEN
        event_type IN 'Approved'
        OR date_diff(
          LEAD(timestamp_utc, 1)
            OVER (PARTITION BY user_id ORDER BY timestamp_utc),
          timestamp_utc
        ) >= 4
      THEN 1
      ELSE 0
    END AS session_end_indicator
  FROM events_table
)

SELECT
  timestamp_utc,
  user_id,
  event_type,
  token,
  COALESCE(
    LEAD(session_end_indicator)
      OVER (PARTITION BY user_id ORDER BY timestamp_utc),
    0
  ) AS start_of_session   
```

| timestamp_utc       | user_id | token | event_type    | session_end_indicator |
|:--------------------|:--------|:------|:--------------|:----------------------|
| 2021-01-01 09:12:12 | 1       | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | 1       | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | 1       | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | 1       | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | 1       | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | 1       |       | Approved      | 0                     |
| 2021-01-01 20:25:44 | 1       | B1    | Add product C | 1                     |
| 2021-01-06 21:25:37 | 1       | A3    | Add product C | 1                     |
| 2021-01-06 21:35:47 | 1       | A3    | Checkout      | 0                     |
| 2021-01-06 21:33:48 | 1       |       | Approved      | 0                     |
| 2021-01-06 21:34:08 | 1       | A3    | Add product D | 1                     |
| 2021-01-01 16:35:14 | 2       | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | 2       | A2    | Add product B | 0                     |
| 2021-01-05 23:55:19 | 2       | B2    | Add product B | 1                     |
| 2021-01-06 00:01:21 | 2       | B2    | Checkout      | 0                     |
| 2021-01-06 00:01:21 | 2       |       | Approved      | 0                     |
| 2021-01-06 00:05:19 | 2       | B2    | Add product C | 1                     |
| 2021-01-06 21:35:47 | 2       | A2    | Checkout      | 0                     |

And finally, we run a cumulative sum over the indicator, which will give us a per-user session ID, starting with 0

```
WITH end_of_sessions AS (
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

SELECT
  timestamp_utc,
  user_id,
  event_type,
  token,
  SUM(session_start_indicator)
    OVER (PARTITION BY user_id ORDER BY timestamp_utc ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
  AS user_session_id
FROM start_of_sessions
```

| timestamp_utc       | user_id | token | event_type    | user_session_id       |
|:--------------------|:--------|:------|:--------------|:----------------------|
| 2021-01-01 09:12:12 | 1       | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | 1       | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | 1       | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | 1       | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | 1       | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | 1       |       | Approved      | 0                     |
| 2021-01-01 20:25:44 | 1       | B1    | Add product C | 1                     |
| 2021-01-06 21:25:37 | 1       | A3    | Add product C | 2                     |
| 2021-01-06 21:35:47 | 1       | A3    | Checkout      | 2                     |
| 2021-01-06 21:33:48 | 1       |       | Approved      | 2                     |
| 2021-01-06 21:34:08 | 1       | A3    | Add product D | 3                     |
| 2021-01-01 16:35:14 | 2       | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | 2       | A2    | Add product B | 0                     |
| 2021-01-05 23:55:19 | 2       | B2    | Add product B | 1                     |
| 2021-01-06 00:01:21 | 2       | B2    | Checkout      | 1                     |
| 2021-01-06 00:01:21 | 2       |       | Approved      | 1                     |
| 2021-01-06 00:05:19 | 2       | B2    | Add product C | 2                     |
| 2021-01-06 21:35:47 | 2       | A2    | Checkout      | 2                     |

And we can continue our analysis by session

```
SELECT
  user_id,
  user_session_id
  SUM(CASE WHEN event_type = 'Approved' THEN 1 ELSE 0 END) AS purchase_count
  SUM(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS checkout_attempts 
  COUNT( DISTINCT CASE WHEN event_type LIKE 'pathView%' THEN event_type ELSE NULL END) AS distinct_pageviews_count 
  ...
FROM sessions
GROUP BY user_id, user_session_id
```


## Full SQL code

