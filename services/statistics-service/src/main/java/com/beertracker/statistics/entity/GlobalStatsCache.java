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
@Table(name = "global_stats_cache")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class GlobalStatsCache {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(name = "active_users")
    private Integer activeUsers;

    @Column(name = "global_avg_drinks_per_day", precision = 5, scale = 2)
    private BigDecimal globalAvgDrinksPerDay;

    /**
     * JSON array of top beer name strings, e.g. ["Lager X", "Pale Ale Y"].
     * Stored as JSONB in PostgreSQL.
     */
    @Type(JsonType.class)
    @Column(name = "top_beer_names", columnDefinition = "jsonb")
    private String topBeerNames;

    @Column(name = "cached_at", nullable = false)
    private OffsetDateTime cachedAt;
}
