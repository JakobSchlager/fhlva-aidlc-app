package com.beertracker.tracking.dto;

import java.math.BigDecimal;
import java.util.UUID;

public record SummaryResponse(
        UUID userId,
        long totalEntries,
        long totalVolumeMl,
        BigDecimal totalStandardDrinks
) {
}
