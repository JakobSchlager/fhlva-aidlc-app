package com.beertracker.statistics.repository;

import com.beertracker.statistics.entity.DailyTrendCache;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

@Repository
public interface DailyTrendCacheRepository extends JpaRepository<DailyTrendCache, UUID> {

    /**
     * Returns all daily trend cache entries for a user within the given date range (inclusive).
     */
    List<DailyTrendCache> findByUserIdAndTrendDateBetween(UUID userId, LocalDate from, LocalDate to);

    /**
     * Returns cached trend dates for a user, used to identify which days still need fetching.
     */
    @Query("SELECT d.trendDate FROM DailyTrendCache d WHERE d.userId = :userId")
    Set<LocalDate> findTrendDatesByUserId(UUID userId);

    /**
     * Retrieves a single entry for a specific user and date.
     */
    Optional<DailyTrendCache> findByUserIdAndTrendDate(UUID userId, LocalDate trendDate);

    /**
     * Deletes entries older than the specified date for a user (used for cache eviction).
     */
    @Modifying
    @Query("DELETE FROM DailyTrendCache d WHERE d.userId = :userId AND d.trendDate < :cutoffDate")
    void deleteByUserIdAndTrendDateBefore(UUID userId, LocalDate cutoffDate);
}
