package com.beertracker.statistics.repository;

import com.beertracker.statistics.entity.GlobalStatsCache;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.Optional;
import java.util.UUID;

@Repository
public interface GlobalStatsCacheRepository extends JpaRepository<GlobalStatsCache, UUID> {

    /**
     * Returns the most recently cached global statistics snapshot.
     */
    Optional<GlobalStatsCache> findFirstByOrderByCachedAtDesc();

    /**
     * Removes all stale global stats snapshots. Called before inserting a new snapshot
     * so the table stays bounded to a single current row.
     * Uses a native query to avoid JPQL limitations with subquery ordering.
     */
    @Modifying
    @Query(value = """
        DELETE FROM global_stats_cache
        WHERE id NOT IN (
            SELECT id FROM global_stats_cache
            ORDER BY cached_at DESC
            LIMIT 1
        )
        """, nativeQuery = true)
    void deleteAllExceptLatest();
}
