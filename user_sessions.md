# Defining user-sessions from events & pageViews in SQL

## What's in a session

Good news! Your engineers finally got around to implementing pageView tracking and maybe some custom events (buttons clicked, backend events like checkout confirmation, etc). It's time to start figuring out what your users are *actually* doing with your product.

Counting tokens & clicks is great place to start (and quite often, all you really need), but you want to dive a bit deeper. KPIs like [total clicks] / [total product paveViews] are good overall metrics, but will not tell you that 90% of your users always click while 10% of your users just browse around "aimlessly" (hello crawler bots!). Even at the user level (GROUP BY user ID, right?) you are still missing part of the picture - for example which of your "click & buy" campaigns lead users to making a purchase? Are there landing pages that work better than others? etc...

*Enters "the session"*


### Oh, but there's more than one definition

A "session" is a is a much (ab)used term. This post looks at sessions from a *behavioural perspective*: A user performing a task or going through a flow in your product (in our example - users buying products). Intuitively I think we all get it, but the definition becomes harder when you mix in the other definitions of a "session":

- **Login sessions:** This is really good data - both login and logout are "strong" indication for a beginning/end of a workflow. But unless you're working on secure app (finance / banking etc ) good luck getting those. For most of us the user stays logged in "forver", or at least until the cooking expires.

- **Timeout sessions:** This can be as random as "30 minute timeout"/"cookie lives for 7 days" rule. These sessions can be a good place to start but, but you may discover that they are very sensitive to the definitions. Consider the long tail of users that take their time deciding: under the "30 min" rule they might generate hundreds / thousands of "no-click" sessions (instead of one long successful one) that will play havoc with your conversion rates.

- **Event driven sessions:** In an ideal world you have your workflows unambigouosly defined, synchronious events for every stage of the flow and all systems are firing to a single endpoint 100% of the time while your pet unicorn makes you the perfect espresso. In reality, well... this is what this post is for.

- **Backend/frontend sessions:** Your backend might have it's own idea about what a session means. In our case, we don't guarantee the prices in the cart for more than 4 days, and we decided that the cart will simply expire. Oh, and because we're low on resources we but we haven't implemented these events yet (so all you have is a time limit). Most frontend tracking tools come with their own baked-in definition - typically timeout based, or (hopefully) with a bit more thought behind it, but without serious investment you will not be able to sync these sessions with your backend. Typically your backend is not aware of the tracking that's happening on the front end, meaning that backend events don't have the frontend's session token, and the frontend will not fire a paveView or a new event when the cart expires.


### Session fencing

So what we're dealing here is a mixed stream of events from different sources, combined with some time limits we have to apply. In my experience, it's usually easier to define when a session ends than when a session starts under these circumstances. Daily logins are no longer a thing for most of us (unless you're working on a banking app, which will kick you out in the name of security) and multi-tab browsing makes it event more complicated to figure out when users begin a process. On the other hand, some events in our systems are "absolute" indicators of session end ("checkout confirmation", "flow completed" etc) or come from the backend side (your shopping cart is cleared after X days).

Think about it this way: aggregating event / ledger data into meaningful sessions is an exercise in fencing - not the sword kind but the kind that makes good neighbours. We recognise the fact that we are looking at a "messy" stream of data - forgotten tabs, users wandering about, different systems sending different signals etc. What we want is to find strong indication of sessions ending (a "fence"), and in between those endings we have the *"behavioural session"*.

## Example

In this example I will demonstrate a mix of two of these "fences":

- Backend confirms end of transaction ('Approved')
- Time-out: Our cart is "abandoned" after a few days of inactivity

We observe the following behaviours in our data:

- User 1 started on a browser with 2 open tabs, added 2 products (A/B), and then completed the activity on a tablet app that evening.
- The same user also added a product to cart immediately after checkout, but resumed shopping 5 days later (so the cart expired in between)
- User 2 added one product B to the cart and after forgetting about it for a few days tried again (the tab remained opened but the cart expired). The tracking cookie expired in between the events
- Our backend event that track approval of a checkout do not have the token, only the user ID.

We generate the data trail to reflect these behaviours:

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

| timestamp utc       | user id | token | event type    |
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

| timestamp utc       | user id | token | event type    |
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
| 2021-01-01 20:25:44 | uuid001 | B1    | Add product C | 1                     |
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

| timestamp utc       | user id | token | event type    | session end indicator |
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

| timestamp utc       | user id | token | event type    | user session id       |
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

| user id | user session id | purchase count | checkout attempts | distinct pageviews count |
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
