# What's in a session

Good news! Your engineers finally got around to implementing pageView tracking and maybe some custom events (buttons clicked, backend events like checkout confirmation, etc). It's time to start figuring out what your users are *actually* doing with your product.

## Why sessions

Counting tokens & clicks is great place to start (and quite often, all you really need), but you want to dive a bit deeper. KPIs like [total clicks] / [total product paveViews] are good overall metrics, but will not tell you that 90% of your users always click while 10% of your users just browse around "aimlessly" (hello crawler bots!). Even at the user level (GROUP BY user ID, right?) you are still missing part of the picture - for example which of your "click & buy" campaigns lead users to making a purchase? Are there landing pages that work better than others? etc...

*Enters "the session"*


### Oh, but there's more than one definition

A "session" is a is a much (ab)used term. This post looks at sessions from a behavioural perspective: A user performing a task or going through a flow in your product (in our example - users buying products). Intuitively I think we all get it, but the definition becomes harder when you mix in the other definitions of a "session":

- Most frontend tracking tools come with their own baked-in definition. This can be as random as "30 minute timeout", or the new "cookie lives for 7 days" rule

- Your backend might have it's own idea about a session, in our 4-day the cart expires on the backend (but we haven't implemented these events yet)

- And of course, these two (front/backend) might not be on good speaking terms: your backend is not aware of the tracking that's happening on the front end, meaning that backend events don't have the frontend's session token

### Session fencing

In most cases I've seen, it's easier to define when a session ends than when a session starts. Logins are not really a thing for most of us (unless you're working on a banking app, which will kick you out in the name of security) and multi-tab browsing makes it event more complicated to figure out when users begin a process. On the other hand, some events in our systems are "absolute" indicators of session end (think "check confirmation", "flow completed" etc) or come from the system side (your shopping cart is cleared after X days).

Think about it this way: aggregating event / ledger data into meaningful sessions is an exercise in fencing - not the sword kind but the kind that makes good neighbours. We recognise the fact that we are looking at a "messy" stream of data - forgotten tabs, users wandering about, different systems sending different signals etc. What we want is to find strong indication of sessions ending (a "fence"), end in between those endings we have the "behavioural session".

## Example

In this example I will demonstrate a mix of two of these "fences":

- Backend confirms end of transaction ('Approved')
- Frontend time-out: Our cart is "abandoned" after a few days of inactivity

We observe the following behaviours in our data:

- User 1 started on a browser with 2 open tabs, added 2 products (A/B), and then completed the activity on a tablet app that evening.
- The same user also added a product to cart immediately after checkout, but resumed shopping 5 days later (so the cart expired in between)
- User 2 added one product B to the cart and after forgetting about it for a few days tried again (the tab remained opened but the cart expired). The tracking cookie expired in between the events
- Our backend event that track approval of a checkout do not have the token, only the user ID.

We generate some data to reflect these behaviours:

```sql
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
```

The event ledger (rows come in by timestamp) looks like this:

```sql
SELECT * FROM events_table
```

| timestamp_utc       | user_id | token | event_type    |
|:--------------------|:--------|:------|:--------------|
| 2021-01-01 09:12:12 | uuid001 | A1    | pageView A    |
| 2021-01-01 09:12:15 | uuid001 | A1    | pageView B    |
| 2021-01-01 09:13:13 | uuid001 | A1    | Add product A |
| 2021-01-01 09:15:01 | uuid001 | A1    | Add product B |
| 2021-01-01 16:35:14 | uuid002 | A2    | pageView B    |
| 2021-01-01 17:15:01 | uuid002 | A2    | Add product B |
| 2021-01-01 20:23:15 | uuid001 | B1    | Checkout      |
| 2021-01-01 20:23:16 | uuid001 |       | Approved      |
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C |
| 2021-01-05 23:55:19 | uuid002 | B2    | Add product B |
| 2021-01-06 00:01:21 | uuid002 | B2    | Checkout      |
| 2021-01-06 00:01:21 | uuid002 |       | Approved      |
| 2021-01-06 00:05:19 | uuid002 | B2    | Add product C |
| 2021-01-06 21:35:47 | uuid002 | A2    | Checkout      |
| 2021-01-06 21:25:37 | uuid001 | A3    | Add product C |
| 2021-01-06 21:35:47 | uuid001 | A3    | Checkout      |
| 2021-01-06 21:33:48 | uuid001 |       | Approved      |
| 2021-01-06 21:34:08 | uuid001 | A3    |  PageView D   |


There's no need to actually sort the data by user & date, but it would help our visualisation:

```sql
SELECT * FROM events_table ORDER BY user_id, timestamp_utc
```

| timestamp_utc       | user_id | token | event_type    |
|:--------------------|:--------|:------|:--------------|
| 2021-01-01 09:12:12 | uuid001 | A1    | pageView A    |
| 2021-01-01 09:12:15 | uuid001 | A1    | pageView B    |
| 2021-01-01 09:13:13 | uuid001 | A1    | Add product A |
| 2021-01-01 09:15:01 | uuid001 | A1    | Add product B |
| 2021-01-01 20:23:15 | uuid001 | B1    | Checkout      |
| 2021-01-01 20:23:16 | uuid001 |       | Approved      |
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C |
| 2021-01-06 21:25:37 | uuid001 | A3    | Add product C |
| 2021-01-06 21:35:47 | uuid001 | A3    | Checkout      |
| 2021-01-06 21:33:48 | uuid001 |       | Approved      |
| 2021-01-06 21:34:08 | uuid001 | A3    |  PageView D   |
| 2021-01-01 16:35:14 | uuid002 | A2    | pageView B    |
| 2021-01-01 17:15:01 | uuid002 | A2    | Add product B |
| 2021-01-05 23:55:19 | uuid002 | B2    | Add product B |
| 2021-01-06 00:01:21 | uuid002 | B2    | Checkout      |
| 2021-01-06 00:01:21 | uuid002 |       | Approved      |
| 2021-01-06 00:05:19 | uuid002 | B2    | Add product C |
| 2021-01-06 21:35:47 | uuid002 | A2    | Checkout      |


Let's flag our "fences" - when a checkout is complete or when the cart is older than 4 days:

```sql
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
```

| timestamp_utc       | user_id | token | event_type    | session_end_indicator |
|:--------------------|:--------|:------|:--------------|:----------------------|
| 2021-01-01 09:12:12 | uuid001 | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | uuid001 | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | uuid001 | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | uuid001 | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | uuid001 | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | uuid001 |       | Approved      | 1                     |
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C | 0                     |
| 2021-01-06 21:25:37 | uuid001 | A3    | Add product C | 0                     |
| 2021-01-06 21:35:47 | uuid001 | A3    | Checkout      | 0                     |
| 2021-01-06 21:33:48 | uuid001 |       | Approved      | 1                     |
| 2021-01-06 21:34:08 | uuid001 | A3    |  PageView D   | 0                     |
| 2021-01-01 16:35:14 | uuid002 | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | uuid002 | A2    | Add product B | 1                     |
| 2021-01-05 23:55:19 | uuid002 | B2    | Add product B | 0                     |
| 2021-01-06 00:01:21 | uuid002 | B2    | Checkout      | 0                     |
| 2021-01-06 00:01:21 | uuid002 |       | Approved      | 1                     |
| 2021-01-06 00:05:19 | uuid002 | B2    | Add product C | 0                     |
| 2021-01-06 21:35:47 | uuid002 | A2    | Checkout      | 0                     |


We then move the "end of session" market a step forward so we get a "start of next session" indicator

```sql
WITH end_of_sessions AS (
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
)

SELECT
  timestamp_utc,
  user_id,
  event_type,
  token,
  COALESCE(
    LAG(session_end_indicator, 1)
      OVER (PARTITION BY user_id ORDER BY timestamp_utc),
    0
  ) AS session_start_indicator
FROM end_of_sessions
```

| timestamp_utc       | user_id | token | event_type    | session_end_indicator |
|:--------------------|:--------|:------|:--------------|:----------------------|
| 2021-01-01 09:12:12 | uuid001 | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | uuid001 | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | uuid001 | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | uuid001 | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | uuid001 | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | uuid001 |       | Approved      | 0                     |
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C | 1                     |
| 2021-01-06 21:25:37 | uuid001 | A3    | Add product C | 1                     |
| 2021-01-06 21:35:47 | uuid001 | A3    | Checkout      | 0                     |
| 2021-01-06 21:33:48 | uuid001 |       | Approved      | 0                     |
| 2021-01-06 21:34:08 | uuid001 | A3    |  PageView D   | 1                     |
| 2021-01-01 16:35:14 | uuid002 | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | uuid002 | A2    | Add product B | 0                     |
| 2021-01-05 23:55:19 | uuid002 | B2    | Add product B | 1                     |
| 2021-01-06 00:01:21 | uuid002 | B2    | Checkout      | 0                     |
| 2021-01-06 00:01:21 | uuid002 |       | Approved      | 0                     |
| 2021-01-06 00:05:19 | uuid002 | B2    | Add product C | 1                     |
| 2021-01-06 21:35:47 | uuid002 | A2    | Checkout      | 0                     |

And finally, we run a cumulative sum over the indicator, which will give us a per-user session ID, starting with 0

```sql
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
    COALESCE(
      LAG(session_end_indicator, 1)
        OVER (PARTITION BY user_id ORDER BY timestamp_utc),
      0
    ) AS session_start_indicator
  FROM end_of_sessions
),

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
| 2021-01-01 09:12:12 | uuid001 | A1    | pageView A    | 0                     |
| 2021-01-01 09:12:15 | uuid001 | A1    | pageView B    | 0                     |
| 2021-01-01 09:13:13 | uuid001 | A1    | Add product A | 0                     |
| 2021-01-01 09:15:01 | uuid001 | A1    | Add product B | 0                     |
| 2021-01-01 20:23:15 | uuid001 | B1    | Checkout      | 0                     |
| 2021-01-01 20:23:16 | uuid001 |       | Approved      | 0                     |
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C | 1                     |
| 2021-01-06 21:25:37 | uuid001 | A3    | Add product C | 2                     |
| 2021-01-06 21:35:47 | uuid001 | A3    | Checkout      | 2                     |
| 2021-01-06 21:33:48 | uuid001 |       | Approved      | 2                     |
| 2021-01-06 21:34:08 | uuid001 | A3    |  PageView D   | 3                     |
| 2021-01-01 16:35:14 | uuid002 | A2    | pageView B    | 0                     |
| 2021-01-01 17:15:01 | uuid002 | A2    | Add product B | 0                     |
| 2021-01-05 23:55:19 | uuid002 | B2    | Add product B | 1                     |
| 2021-01-06 00:01:21 | uuid002 | B2    | Checkout      | 1                     |
| 2021-01-06 00:01:21 | uuid002 |       | Approved      | 1                     |
| 2021-01-06 00:05:19 | uuid002 | B2    | Add product C | 2                     |
| 2021-01-06 21:35:47 | uuid002 | A2    | Checkout      | 2                     |

And we can continue our analysis by session

```sql
SELECT
  user_id,
  user_session_id
  SUM(CASE WHEN event_type = 'Approved' THEN 1 ELSE 0 END) AS purchase_count,
  SUM(CASE WHEN event_type = 'Checkout' THEN 1 ELSE 0 END) AS checkout_attempts,
  COUNT( DISTINCT CASE WHEN event_type LIKE 'pageView%' THEN event_type ELSE NULL END) AS distinct_pageviews_count
  ...
FROM user_sessions
GROUP BY user_id, user_session_id
ORDER BY user_id, user_session_id
```

And get:

| user_id | user_session_id | purchase_count | checkout_attempts | distinct_pageviews_count |
|---------|-----------------|----------------|-------------------|--------------------------|
| uid001  | 0               | 1              | 1                 | 2                        |
| uid001  | 1               | 0              | 0                 | 0                        |
| uid001  | 2               | 1              | 0                 | 0                        |
| uid001  | 3               | 0              | 1                 | 1                        |
| uid002  | 0               | 0              | 0                 | 1                        |
| uid002  | 1               | 1              | 1                 | 0                        |
| uid002  | 2               | 0              | 1                 | 0                        |

## Full SQL code

You can find the full code in [this file](user_sessions.sql)
