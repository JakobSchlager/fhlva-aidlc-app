package com.beertracker.statistics.entity;

import io.hypersistence.utils.hibernate.type.json.JsonType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.Type;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "personal_stats_cache")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PersonalStatsCache {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(name = "user_id", columnDefinition = "uuid", unique = true, nullable = false)
    private UUID userId;

    @Column(name = "total_entries")
    private Integer totalEntries;

    @Column(name = "total_volume_ml")
    private Long totalVolumeMl;

    @Column(name = "total_standard_drinks", precision = 10, scale = 2)
    private BigDecimal totalStandardDrinks;

    @Column(name = "avg_drinks_per_day_30d", precision = 5, scale = 2)
    private BigDecimal avgDrinksPerDay30d;

    /**
     * JSON array of {dayName, avgDrinks} objects, Monday through Sunday.
     * Stored as JSONB in PostgreSQL and serialised/deserialised by the service layer
     * using ObjectMapper.
     */
    @Type(JsonType.class)
    @Column(name = "by_day_of_week", columnDefinition = "jsonb")
    private String byDayOfWeek;

    @Column(name = "cached_at", nullable = false)
    private OffsetDateTime cachedAt;
}
