package com.beertracker.statistics.dto;

import java.math.BigDecimal;

/**
 * Average standard drinks for one day of the week (Monday through Sunday).
 */
public record DayOfWeekStat(String dayName, BigDecimal avgDrinks) {
}
