[Back to my projects page](/)

[Back to Coding in SQL](/sql-code)

# Kernel smoothing in SQL: temporal, cicular and other beasts

![kernel smoothing](https://en.wikipedia.org/wiki/File:Gaussian_kernel_regression.png)

## Smoothing things over

Lets generate some data - we look at a noisy (and jittery) signal over a few days:

```sql
CREATE OR REPLACE TABLE measurements AS
SELECT *
FROM (VALUES
    (1001, CAST('2021-07-05' AS DATE), 10.45),
    (1001, CAST('2021-07-06' AS DATE), 9.64),
    (1001, CAST('2021-07-07' AS DATE), 10.45),
    (1001, CAST('2021-07-08' AS DATE), 10.27),
    (1001, CAST('2021-07-09' AS DATE), 12.2),
    (1001, CAST('2021-07-10' AS DATE), 22.55),
    (1001, CAST('2021-07-11' AS DATE), 20.78),
    (1001, CAST('2021-07-12' AS DATE), 15.4),
    (1001, CAST('2021-07-13' AS DATE), 9.36),
    (1001, CAST('2021-07-14' AS DATE), 10.77),
    (1001, CAST('2021-07-15' AS DATE), 12.81),
    (1001, CAST('2021-07-16' AS DATE), 8.35),
    (1001, CAST('2021-07-17' AS DATE), 19.54),
    (1001, CAST('2021-07-18' AS DATE), 18.91)
) AS t(user_id, date, measurement)

```

```sql
SELECT date, measurement FROM measurements
```

| date       | meansurement |
|:-----------|:-------------|
| 2021-07-05 | 10.45        |
| 2021-07-06 | 9.64         |
| 2021-07-07 | 10.45        |
| 2021-07-08 | 10.27        |
| 2021-07-09 | 12.2         |
| 2021-07-10 | 22.55        |
| 2021-07-11 | 20.78        |
| 2021-07-12 | 15.4         |
| 2021-07-13 | 9.36         |
| 2021-07-14 | 10.77        |
| 2021-07-15 | 12.81        |
| 2021-07-16 | 8.35         |
| 2021-07-17 | 19.54        |
| 2021-07-18 | 18.91        |



### The moving average

One of the simplest ways of "smoothing" a series of values is the [moving average](https://en.wikipedia.org/wiki/Moving_average). According to Wikipedia, this is in fact [the simplest kernel smoother](https://en.wikipedia.org/wiki/Kernel_smoother) out there so it's a good place to start and understand what smoothing can do for you. An implementation of a moving average exists in pracically all SQL dialects as a one-liner, using window functions. For example a 5 day moving window can be implemented as:

```
SELECT
  m.date
  ,m.measurement
  ,AVG(m.measurement)
    OVER (PARTITION BY m.user_id ORDER BY m.date ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS moving_avg_5_days
```

| date       | meansurement | moving_avg_5_days |
|:-----------|:-------------|:------------------|
| 2021-07-05 | 10.45        | 10.18             |
| 2021-07-06 | 9.64         | 10.2025           |
| 2021-07-07 | 10.45        | 10.602            |
| 2021-07-08 | 10.27        | 13.022            |
| 2021-07-09 | 12.2         | 15.25             |
| 2021-07-10 | 22.55        | 16.24             |
| 2021-07-11 | 20.78        | 16.058            |
| 2021-07-12 | 15.4         | 15.772            |
| 2021-07-13 | 9.36         | 13.824            |
| 2021-07-14 | 10.77        | 11.338            |
| 2021-07-15 | 12.81        | 12.166            |
| 2021-07-16 | 8.35         | 14.076            |
| 2021-07-17 | 19.54        | 14.9025           |
| 2021-07-18 | 18.91        | 15.6              |



### Kernel weights (not all days are the same)

What is kernel smoothing? Well you've just seen in action. A moving average is a form of kernel smoothing where all observations inside the window get the same weight. We can introduce more complex ideas of smoothing by changing the weights. For example: What if we wanted to give "closer" days higher weights?


```
                window range
     <----------------------------->
     | 10% | 20% | 40% | 20% | 10% |
...--|-----|-----|-----|-----|-----|-----|--...
day  1     2     3     4     5     6     7

```

The mose generic (and safe) way to specify weights is to use an explicit `CASE WHEN` statement. This allows for any kind of window and also for non-symmetrics weights:

```sql
CASE
  WHEN reference_date - window_date = -2 THEN 0.1
  WHEN reference_date - window_date = -1 THEN 0.2
  WHEN reference_date - window_date = 0  THEN 0.4
  WHEN reference_date - window_date = 1  THEN 0.2
  WHEN reference_date - window_date = 2  THEN 0.1
  ELSE 0
END
```

Where `reference_date` is the date we want to calculate and `window_date` are the values inside the window.

But we can also use some simple math and normalize later. We want to assign


| place | weight |
|:------|:-------|
| -2    | 1      |
| -1    | 2      |
| 0     | 4      |
| 1     | 2      |
| 2     | 1      |

and a normalization factor of ```1 + 2 + 4 + 2 + 1 = 10```. We can use ```POWER(2, 2 - abs(reference_date - window_date))``` as a short way to calculate these weights inside the window:


```sql
SELECT
  m.user_id
  ,m.date
  ,MIN(m.measurement) AS measurement
  ,SUM(m.measurement) / COUNT(1) AS moving_avg
  ,SUM(POWER(2, 2 - abs(m.date - m2.date)) * m2.measurement) / 10.0 AS moving_weighted_avg
FROM measurements m
  LEFT JOIN measurements m2
    ON m2.user_id = m.user_id
    AND m2.date >= m.date - INTERVAL '2' DAY
    AND m2.date <= m.date + INTERVAL '2' DAY
GROUP BY 1,2
```

And get

| user_id | date | measurement | moving_avg | moving_weighted_average |
|:--------|:-----|:------------|:-----------|:------------------------|
1001|2021-07-05|10.45|10.18|7.153|
1001|2021-07-06|9.64|10.2025|9.063|
1001|2021-07-07|10.45|10.602|10.427|
1001|2021-07-08|10.27|13.022|11.857|
1001|2021-07-09|12.2|15.25|14.567|
1001|2021-07-10|22.55|16.24|18.183|
1001|2021-07-11|20.78|16.058|18.058|
1001|2021-07-12|15.4|15.772|15.52|
1001|2021-07-13|9.36|13.824|12.337|
1001|2021-07-14|10.77|11.338|11.117|
1001|2021-07-15|12.81|12.166|11.838|
1001|2021-07-16|8.35|14.076|12.778|
1001|2021-07-17|19.54|14.9025|14.549|
1001|2021-07-18|18.91|15.6|12.307|


### Smoothing over missing values



## Making it circular

Add day-of-week

```sql
SELECT
  user_id
  ,date
  ,date_format(date, 'E') AS day_of_week
  ,measurement
```
