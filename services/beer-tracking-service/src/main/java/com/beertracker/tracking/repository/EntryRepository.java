package com.beertracker.tracking.repository;

import com.beertracker.tracking.entity.Entry;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Repository
public interface EntryRepository extends JpaRepository<Entry, UUID> {

    Page<Entry> findByUserId(UUID userId, Pageable pageable);

    Page<Entry> findByUserIdAndTimestampBetween(UUID userId, Instant from, Instant to, Pageable pageable);

    List<Entry> findByUserIdAndTimestampBetween(UUID userId, Instant from, Instant to);

    @Query("SELECT DISTINCT e.userId FROM Entry e")
    List<UUID> findDistinctUserIds();
}
