package com.beertracker.statistics.repository;

import com.beertracker.statistics.entity.PersonalStatsCache;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface PersonalStatsCacheRepository extends JpaRepository<PersonalStatsCache, UUID> {

    Optional<PersonalStatsCache> findByUserId(UUID userId);

    /**
     * Returns all user IDs that have an entry in the personal stats cache.
     * Used by the scheduler to determine which users to refresh.
     */
    List<PersonalStatsCache> findAll();
}
