package com.beertracker.statistics.service;

import com.beertracker.statistics.dto.DayOfWeekStat;
import com.beertracker.statistics.dto.TrackingInternalSummaryResponse;
import com.beertracker.statistics.entity.DailyTrendCache;
import com.beertracker.statistics.entity.GlobalStatsCache;
import com.beertracker.statistics.entity.PersonalStatsCache;
import com.beertracker.statistics.repository.DailyTrendCacheRepository;
import com.beertracker.statistics.repository.GlobalStatsCacheRepository;
import com.beertracker.statistics.repository.PersonalStatsCacheRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Handles all cache-refresh logic — fetching data from the tracking service and
 * persisting updated cache entries. Used by both the scheduler and on-demand calls
 * from {@link StatisticsService}.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StatisticsRefreshService {

    /** How many days of daily trend data to keep in the cache per user. */
    private static final int TREND_HISTORY_DAYS = 365;

    /** Rolling window within which we always re-fetch from the tracking service. */
    private static final int REFRESH_WINDOW_DAYS = 7;

    private final TrackingServiceClient trackingServiceClient;
    private final PersonalStatsCacheRepository personalStatsCacheRepository;
    private final GlobalStatsCacheRepository globalStatsCacheRepository;
    private final DailyTrendCacheRepository dailyTrendCacheRepository;
    private final ObjectMapper objectMapper;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /**
     * Refreshes personal stats and daily trend data for a single user.
     * Runs in its own independent transaction so it can be called safely from both
     * the scheduler and from within a read-only service transaction.
     * On any tracking service failure the method logs a warning and returns without
     * modifying existing cached data (stale cache is preserved).
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void refreshUserStats(UUID userId) {
        log.debug("Refreshing personal stats for userId={}", userId);
        LocalDate today = LocalDate.now(ZoneOffset.UTC);

        try {
            // 1. All-time totals
            Optional<TrackingInternalSummaryResponse> allTime = trackingServiceClient
                    .getSummary(userId, LocalDate.of(2000, 1, 1), today);
            if (allTime.isEmpty()) {
                log.warn("No all-time summary returned for userId={}, skipping refresh", userId);
                return;
            }

            // 2. 30-day window for avgDrinksPerDay
            LocalDate thirtyDaysAgo = today.minusDays(30);
            Optional<TrackingInternalSummaryResponse> last30 = trackingServiceClient
                    .getSummary(userId, thirtyDaysAgo, today);

            BigDecimal avgDrinksPerDay30d = last30
                    .map(r -> divide(r.totalStandardDrinks(), 30))
                    .orElse(BigDecimal.ZERO);

            // 3. Refresh daily trend data — skip for users with no entries (all days are zero)
            TrackingInternalSummaryResponse summary = allTime.get();
            int entryCount = summary.totalEntries() != null ? summary.totalEntries() : 0;
            if (entryCount > 0) {
                refreshDailyTrend(userId, today);
            }

            // 4. Compute byDayOfWeek from trend data
            String byDayOfWeekJson = entryCount > 0 ? computeByDayOfWeekJson(userId) : "[]";

            // 5. Evict trend entries older than TREND_HISTORY_DAYS
            dailyTrendCacheRepository.deleteByUserIdAndTrendDateBefore(
                    userId, today.minusDays(TREND_HISTORY_DAYS));

            // 6. Upsert personal stats cache
            personalStatsCacheRepository.findByUserId(userId).ifPresentOrElse(
                    existing -> {
                        existing.setTotalEntries(summary.totalEntries());
                        existing.setTotalVolumeMl(summary.totalVolumeMl());
                        existing.setTotalStandardDrinks(summary.totalStandardDrinks());
                        existing.setAvgDrinksPerDay30d(avgDrinksPerDay30d);
                        existing.setByDayOfWeek(byDayOfWeekJson);
                        existing.setCachedAt(OffsetDateTime.now(ZoneOffset.UTC));
                        personalStatsCacheRepository.save(existing);
                    },
                    () -> personalStatsCacheRepository.save(PersonalStatsCache.builder()
                            .userId(userId)
                            .totalEntries(summary.totalEntries())
                            .totalVolumeMl(summary.totalVolumeMl())
                            .totalStandardDrinks(summary.totalStandardDrinks())
                            .avgDrinksPerDay30d(avgDrinksPerDay30d)
                            .byDayOfWeek(byDayOfWeekJson)
                            .cachedAt(OffsetDateTime.now(ZoneOffset.UTC))
                            .build())
            );

            log.info("Personal stats refreshed for userId={}", userId);

        } catch (Exception ex) {
            log.warn("Failed to refresh personal stats for userId={}: {}", userId, ex.getMessage(), ex);
            // Do not rethrow — stale cache remains intact
        }
    }

    /**
     * Recomputes global anonymised statistics from data already in the personal stats cache
     * (no individual user data leaks into the global response).
     * Runs in its own independent transaction (REQUIRES_NEW) so it is safe to call
     * from any transaction context, including readOnly ones.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void refreshGlobalStats() {
        log.debug("Refreshing global stats");
        try {
            List<PersonalStatsCache> allUsers = personalStatsCacheRepository.findAll();
            if (allUsers.isEmpty()) {
                log.debug("No users in personal stats cache — skipping global refresh");
                return;
            }

            int activeUsers = allUsers.size();

            BigDecimal sumAvg = allUsers.stream()
                    .map(u -> u.getAvgDrinksPerDay30d() != null ? u.getAvgDrinksPerDay30d() : BigDecimal.ZERO)
                    .reduce(BigDecimal.ZERO, BigDecimal::add);
            BigDecimal globalAvg = divide(sumAvg, activeUsers);

            // topBeerNames requires aggregation across tracking service — stored as empty list
            // until the tracking service exposes a global aggregation endpoint.
            String topBeerNamesJson = "[]";

            GlobalStatsCache globalCache = GlobalStatsCache.builder()
                    .activeUsers(activeUsers)
                    .globalAvgDrinksPerDay(globalAvg)
                    .topBeerNames(topBeerNamesJson)
                    .cachedAt(OffsetDateTime.now(ZoneOffset.UTC))
                    .build();

            globalStatsCacheRepository.save(globalCache);

            // Keep only the latest global snapshot
            try {
                globalStatsCacheRepository.deleteAllExceptLatest();
            } catch (Exception cleanupEx) {
                log.warn("Failed to clean up stale global stats rows: {}", cleanupEx.getMessage());
            }

            log.info("Global stats refreshed: activeUsers={}, globalAvg={}", activeUsers, globalAvg);

        } catch (Exception ex) {
            log.warn("Failed to refresh global stats: {}", ex.getMessage(), ex);
        }
    }

    // -------------------------------------------------------------------------
    // Private helpers
    // -------------------------------------------------------------------------

    /**
     * Fetches and persists daily standard-drink totals from the tracking service.
     * Strategy:
     * - Always re-fetch the most recent {@code REFRESH_WINDOW_DAYS} days.
     * - For older days (up to {@code TREND_HISTORY_DAYS}), fetch only if not yet cached.
     */
    private void refreshDailyTrend(UUID userId, LocalDate today) {
        LocalDate cutoff = today.minusDays(TREND_HISTORY_DAYS);
        LocalDate refreshBoundary = today.minusDays(REFRESH_WINDOW_DAYS);

        Set<LocalDate> cachedDates = dailyTrendCacheRepository.findTrendDatesByUserId(userId);

        for (LocalDate date = cutoff; !date.isAfter(today); date = date.plusDays(1)) {
            boolean needsFetch = !cachedDates.contains(date) || date.isAfter(refreshBoundary);
            if (!needsFetch) {
                continue;
            }

            LocalDate fetchDate = date; // effectively final for lambda
            trackingServiceClient.getDailySummary(userId, fetchDate).ifPresent(summary -> {
                BigDecimal drinks = summary.totalStandardDrinks() != null
                        ? summary.totalStandardDrinks()
                        : BigDecimal.ZERO;

                dailyTrendCacheRepository.findByUserIdAndTrendDate(userId, fetchDate)
                        .ifPresentOrElse(
                                existing -> {
                                    existing.setStandardDrinks(drinks);
                                    dailyTrendCacheRepository.save(existing);
                                },
                                () -> dailyTrendCacheRepository.save(DailyTrendCache.builder()
                                        .userId(userId)
                                        .trendDate(fetchDate)
                                        .standardDrinks(drinks)
                                        .build())
                        );
            });
        }
    }

    /**
     * Computes a 7-element Mon–Sun breakdown from all daily trend entries for the user.
     *
     * @return JSON array string, e.g. {@code [{"dayName":"Monday","avgDrinks":1.50}, ...]}
     */
    private String computeByDayOfWeekJson(UUID userId) {
        List<DailyTrendCache> trend = dailyTrendCacheRepository
                .findByUserIdAndTrendDateBetween(userId,
                        LocalDate.now(ZoneOffset.UTC).minusDays(TREND_HISTORY_DAYS),
                        LocalDate.now(ZoneOffset.UTC));

        // Group by day of week (ISO: Mon=1 … Sun=7)
        Map<DayOfWeek, List<BigDecimal>> byDow = trend.stream()
                .filter(t -> t.getStandardDrinks() != null)
                .collect(Collectors.groupingBy(
                        t -> t.getTrendDate().getDayOfWeek(),
                        Collectors.mapping(DailyTrendCache::getStandardDrinks, Collectors.toList())));

        DayOfWeek[] ordered = {
            DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
            DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY, DayOfWeek.SUNDAY
        };

        List<DayOfWeekStat> stats = new ArrayList<>();
        for (DayOfWeek dow : ordered) {
            List<BigDecimal> values = byDow.getOrDefault(dow, List.of());
            BigDecimal avg = values.isEmpty()
                    ? BigDecimal.ZERO
                    : divide(values.stream().reduce(BigDecimal.ZERO, BigDecimal::add), values.size());
            stats.add(new DayOfWeekStat(dow.name().charAt(0) + dow.name().substring(1).toLowerCase(), avg));
        }

        try {
            return objectMapper.writeValueAsString(stats);
        } catch (JsonProcessingException ex) {
            log.error("Failed to serialise byDayOfWeek JSON", ex);
            return "[]";
        }
    }

    private BigDecimal divide(BigDecimal numerator, int denominator) {
        if (numerator == null || denominator == 0) {
            return BigDecimal.ZERO;
        }
        return numerator.divide(BigDecimal.valueOf(denominator), 2, RoundingMode.HALF_UP);
    }
}
