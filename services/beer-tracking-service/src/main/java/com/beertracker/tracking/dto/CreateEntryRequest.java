package com.beertracker.tracking.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.math.BigDecimal;
import java.time.Instant;

public record CreateEntryRequest(
        @NotBlank String beerName,
        @Positive int volumeMl,
        @NotNull @DecimalMin("0.0") @DecimalMax("100.0") BigDecimal abv,
        Instant timestamp
) {
}
