package com.beertracker.notification.repository;

import com.beertracker.notification.entity.Warning;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.entity.Warning.WarningType;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

@Repository
public interface WarningRepository extends JpaRepository<Warning, UUID> {

    Page<Warning> findByUserIdAndStatus(UUID userId, WarningStatus status, Pageable pageable);

    Page<Warning> findByUserId(UUID userId, Pageable pageable);

    Optional<Warning> findByUserIdAndTypeAndStatus(UUID userId, WarningType type, WarningStatus status);

    boolean existsByUserIdAndTypeAndStatus(UUID userId, WarningType type, WarningStatus status);

    /**
     * Returns all distinct user IDs that have at least one warning record.
     * Used by the scheduler to know which users to evaluate even when no
     * consumption data is available from the tracking service.
     */
    @Query("SELECT DISTINCT w.userId FROM Warning w")
    List<UUID> findDistinctUserIds();
}
