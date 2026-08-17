package com.beertracker.statistics.dto;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * Response body for GET /statistics/global
 * Contains only anonymised, aggregated data — no user IDs, emails, or other PII.
 */
public record GlobalStatsResponse(
        Integer activeUsers,
        BigDecimal globalAvgDrinksPerDay,

        /** Top 5 most popular beer names by entry count. */
        List<String> topBeerNames,

        @JsonFormat(shape = JsonFormat.Shape.STRING)
        OffsetDateTime cachedAt
) {
}
