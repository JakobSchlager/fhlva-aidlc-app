package com.beertracker.statistics.dto;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * Response body for GET /statistics/me/trend
 */
public record TrendResponse(
        List<TrendDataPoint> data,

        @JsonFormat(shape = JsonFormat.Shape.STRING)
        OffsetDateTime cachedAt
) {
}
