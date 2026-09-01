CREATE OR REPLACE FUNCTION pg_temp.decode_url_part(p varchar)
RETURNS varchar AS
$$
-- Decode a URL-encoded query parameter value as UTF-8 text.
SELECT convert_from(
    CAST(
        E'\\x' ||
        string_agg(
            CASE
                WHEN length(r.m[1]) = 1
                    THEN encode(
                        convert_to(r.m[1], 'SQL_ASCII'),
                        'hex'
                    )
                ELSE substring(r.m[1] FROM 2 FOR 2)
            END,
            ''
        ) AS bytea
    ),
    'UTF8'
)
FROM regexp_matches(
    replace($1, '+', ' '),
    '%[0-9a-f][0-9a-f]|.',
    'gi'
) AS r(m);
$$ LANGUAGE SQL IMMUTABLE STRICT;

-- Enrich Facebook Ads with dictionary values and align both platforms
-- to a shared analytical schema.
WITH total_ads AS (
    SELECT
        fabd.ad_date AS ad_date,
        fabd.url_parameters AS url_parameters,
        'Facebook' AS media_source,
        fc.campaign_name,
        fa.adset_name,
        COALESCE(fabd.spend, 0) AS spend,
        COALESCE(fabd.impressions, 0) AS impressions,
        COALESCE(fabd.reach, 0) AS reach,
        COALESCE(fabd.clicks, 0) AS clicks,
        COALESCE(fabd.leads, 0) AS leads,
        COALESCE(fabd.value, 0) AS value
    FROM facebook_ads_basic_daily AS fabd
    LEFT JOIN facebook_adset AS fa
        ON fabd.adset_id = fa.adset_id
    LEFT JOIN facebook_campaign AS fc
        ON fabd.campaign_id = fc.campaign_id

    UNION ALL

    SELECT
        ad_date,
        url_parameters,
        'Google' AS media_source,
        campaign_name,
        adset_name,
        COALESCE(spend, 0) AS spend,
        COALESCE(impressions, 0) AS impressions,
        COALESCE(reach, 0) AS reach,
        COALESCE(clicks, 0) AS clicks,
        COALESCE(leads, 0) AS leads,
        COALESCE(value, 0) AS value
    FROM google_ads_basic_daily
),

-- Extract, normalize, and decode the UTM campaign parameter.
decoded_data AS (
    SELECT
        ad_date,
        media_source,
        campaign_name,
        adset_name,

        CASE
            WHEN LOWER(
                SUBSTRING(
                    url_parameters
                    FROM '(?:^|&)utm_campaign=([^&]*)'
                )
            ) IS NULL
                THEN NULL

            WHEN LOWER(
                SUBSTRING(
                    url_parameters
                    FROM '(?:^|&)utm_campaign=([^&]*)'
                )
            ) IN ('', 'nan')
                THEN NULL

            ELSE pg_temp.decode_url_part(
                LOWER(
                    SUBSTRING(
                        url_parameters
                        FROM '(?:^|&)utm_campaign=([^&]*)'
                    )
                )
            )
        END AS utm_campaign,

        spend,
        impressions,
        reach,
        clicks,
        leads,
        value
    FROM total_ads
)

SELECT
    ad_date,
    media_source,
    campaign_name,
    adset_name,
    utm_campaign,
    SUM(spend) AS total_spend,
    SUM(clicks) AS total_clicks,
    SUM(impressions) AS total_impressions,
    SUM(reach) AS total_reach,
    SUM(leads) AS leads,
    SUM(value) AS total_value
FROM decoded_data
GROUP BY
    ad_date,
    media_source,
    campaign_name,
    adset_name,
    utm_campaign
ORDER BY
    ad_date,
    media_source,
    campaign_name,
    adset_name,
    utm_campaign;
