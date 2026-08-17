package com.beertracker.statistics.scheduler;

import com.beertracker.statistics.entity.PersonalStatsCache;
import com.beertracker.statistics.repository.PersonalStatsCacheRepository;
import com.beertracker.statistics.service.StatisticsRefreshService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

/**
 * Periodically refreshes the statistics cache from the beer-tracking-service internal API.
 * <p>
 * The refresh interval is driven by {@code app.statistics.cacheRefreshInterval} (ISO 8601
 * duration, e.g. {@code PT15M}). On failure the scheduler logs a warning and exits
 * gracefully — stale cached data continues to be served until the next successful run.
 * </p>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StatsCacheRefreshScheduler {

    private final PersonalStatsCacheRepository personalStatsCacheRepository;
    private final StatisticsRefreshService refreshService;

    /**
     * Main refresh task. Runs at a fixed rate defined by the
     * {@code app.statistics.cacheRefreshInterval} property (default {@code PT15M}).
     * <p>
     * Strategy:
     * <ol>
     *   <li>Refresh personal stats for every user already in {@code personal_stats_cache}.</li>
     *   <li>Recompute global stats from the freshly updated personal cache.</li>
     * </ol>
     * New users who have not yet been cached are bootstrapped on their first API request
     * via an on-demand call in {@link com.beertracker.statistics.service.StatisticsService}.
     * </p>
     */
    @Scheduled(fixedRateString = "${app.statistics.cacheRefreshInterval:PT15M}")
    public void refreshAllStats() {
        log.info("Starting scheduled statistics cache refresh");

        List<PersonalStatsCache> knownUsers = personalStatsCacheRepository.findAll();
        List<UUID> userIds = knownUsers.stream()
                .map(PersonalStatsCache::getUserId)
                .toList();

        log.info("Refreshing stats for {} known user(s)", userIds.size());

        int refreshed = 0;
        int failed = 0;

        for (UUID userId : userIds) {
            try {
                refreshService.refreshUserStats(userId);
                refreshed++;
            } catch (Exception ex) {
                // refreshUserStats already handles exceptions internally; this is a safety net
                log.warn("Unexpected error during refresh for userId={}: {}", userId, ex.getMessage());
                failed++;
            }
        }

        // Refresh global stats after personal stats are up-to-date
        try {
            refreshService.refreshGlobalStats();
        } catch (Exception ex) {
            log.warn("Unexpected error during global stats refresh: {}", ex.getMessage());
        }

        log.info("Scheduled statistics cache refresh complete: refreshed={}, failed={}", refreshed, failed);
    }
}
