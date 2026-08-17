package com.beertracker.statistics.dto;

import java.math.BigDecimal;
import java.time.LocalDate;

/**
 * A single daily data point in the personal trend time-series.
 */
public record TrendDataPoint(LocalDate date, BigDecimal standardDrinks) {
}
