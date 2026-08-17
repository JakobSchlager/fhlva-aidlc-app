package com.beertracker.statistics.dto;

import java.math.BigDecimal;
import java.util.UUID;

/**
 * Response from the beer-tracking-service internal endpoint:
 * GET /internal/tracking/summary?userId={id}&from={date}&to={date}
 */
public record TrackingInternalSummaryResponse(
        UUID userId,
        Long totalVolumeMl,
        BigDecimal totalStandardDrinks,

        /**
         * Total number of individual consumption entries in the requested window.
         * May be absent (null) if the tracking service does not expose this field.
         */
        Integer totalEntries
) {
}
