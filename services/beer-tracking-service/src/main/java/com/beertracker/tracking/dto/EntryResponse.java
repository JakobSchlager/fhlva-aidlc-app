package com.beertracker.tracking.dto;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

public record EntryResponse(
        UUID id,
        UUID userId,
        String beerName,
        int volumeMl,
        BigDecimal abv,
        Instant timestamp
) {
}
