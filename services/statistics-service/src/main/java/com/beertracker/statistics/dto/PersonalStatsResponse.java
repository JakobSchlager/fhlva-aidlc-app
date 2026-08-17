package com.beertracker.statistics.dto;

import com.fasterxml.jackson.annotation.JsonFormat;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * Response body for GET /statistics/me
 */
public record PersonalStatsResponse(
        Integer totalEntries,
        Long totalVolumeMl,
        BigDecimal totalStandardDrinks,
        BigDecimal avgDrinksPerDay,

        /** Day-of-week breakdown, ordered Monday (index 0) through Sunday (index 6). */
        List<DayOfWeekStat> byDayOfWeek,

        @JsonFormat(shape = JsonFormat.Shape.STRING)
        OffsetDateTime cachedAt
) {
}
