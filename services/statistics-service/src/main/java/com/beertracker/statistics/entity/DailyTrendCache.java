package com.beertracker.statistics.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(
    name = "daily_trend_cache",
    uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "trend_date"})
)
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class DailyTrendCache {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(name = "user_id", columnDefinition = "uuid", nullable = false)
    private UUID userId;

    @Column(name = "trend_date", nullable = false)
    private LocalDate trendDate;

    @Column(name = "standard_drinks", precision = 5, scale = 2)
    private BigDecimal standardDrinks;
}
