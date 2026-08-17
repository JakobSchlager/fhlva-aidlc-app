package com.beertracker.statistics.service;

import com.beertracker.statistics.dto.DayOfWeekStat;
import com.beertracker.statistics.dto.GlobalStatsResponse;
import com.beertracker.statistics.dto.PersonalStatsResponse;
import com.beertracker.statistics.dto.TrendDataPoint;
import com.beertracker.statistics.dto.TrendResponse;
import com.beertracker.statistics.entity.DailyTrendCache;
import com.beertracker.statistics.entity.GlobalStatsCache;
import com.beertracker.statistics.entity.PersonalStatsCache;
import com.beertracker.statistics.repository.DailyTrendCacheRepository;
import com.beertracker.statistics.repository.GlobalStatsCacheRepository;
import com.beertracker.statistics.repository.PersonalStatsCacheRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Reads cached statistics and assembles API responses.
 * <p>
 * Cache refresh is performed asynchronously by {@link com.beertracker.statistics.scheduler.StatsCacheRefreshScheduler}.
 * When stale data is present it is served as-is; the {@code cachedAt} timestamp
 * tells the client when the data was last successfully refreshed.
 * </p>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class StatisticsService {

    private static final int MAX_TREND_DAYS = 365;
    private static final int DEFAULT_TREND_DAYS = 30;

    private final PersonalStatsCacheRepository personalStatsCacheRepository;
    private final GlobalStatsCacheRepository globalStatsCacheRepository;
    private final DailyTrendCacheRepository dailyTrendCacheRepository;
    private final StatisticsRefreshService refreshService;
    private final ObjectMapper objectMapper;

    // -------------------------------------------------------------------------
    // GET /statistics/me
    // -------------------------------------------------------------------------

    /**
     * Returns personal aggregate statistics for the authenticated user.
     *
     * @param userId the authenticated user's ID
     * @param from   optional start date for scoping (null = all time)
     * @param to     optional end date for scoping (null = today)
     * @return personal stats response
     * @throws ResponseStatusException 404 if no cached data is available for the user
     */
    @Transactional(readOnly = true)
    public PersonalStatsResponse getPersonalStats(UUID userId, LocalDate from, LocalDate to) {
        PersonalStatsCache cache = personalStatsCacheRepository.findByUserId(userId)
                .orElseGet(() -> {
                    // First-access bootstrap: attempt a synchronous refresh
                    log.info("No personal stats cache for userId={}, triggering on-demand refresh", userId);
                    refreshService.refreshUserStats(userId);
                    return personalStatsCacheRepository.findByUserId(userId)
                            .orElseThrow(() -> new ResponseStatusException(
                                    HttpStatus.NOT_FOUND,
                                    "No statistics available yet for this user. " +
                                    "Data will be available after the first cache refresh."));
                });

        if (from == null && to == null) {
            // Fast path: return fully cached aggregate
            return mapToPersonalStatsResponse(cache);
        }

        // Date-scoped path: compute from daily_trend_cache for the requested window
        return computeScopedPersonalStats(userId, from, to, cache.getCachedAt());
    }

    // -------------------------------------------------------------------------
    // GET /statistics/me/trend
    // -------------------------------------------------------------------------

    /**
     * Returns a daily standard-drink time series for the authenticated user,
     * zero-filling any days with no cache entry.
     *
     * @param userId the authenticated user's ID
     * @param days   number of past days to include (default 30, max 365)
     * @return trend response with a data point per day
     * @throws ResponseStatusException 400 if {@code days} exceeds 365
     */
    @Transactional(readOnly = true)
    public TrendResponse getTrend(UUID userId, int days) {
        if (days > MAX_TREND_DAYS) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Maximum trend period is " + MAX_TREND_DAYS + " days");
        }

        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        LocalDate from = today.minusDays(days - 1L); // inclusive, so "last N days" = today - (N-1)

        List<DailyTrendCache> cached = dailyTrendCacheRepository
                .findByUserIdAndTrendDateBetween(userId, from, today);

        Map<LocalDate, BigDecimal> byDate = cached.stream()
                .collect(Collectors.toMap(DailyTrendCache::getTrendDate, DailyTrendCache::getStandardDrinks));

        // Build full series with zero-fill for missing days
        List<TrendDataPoint> data = new ArrayList<>(days);
        for (LocalDate d = from; !d.isAfter(today); d = d.plusDays(1)) {
            data.add(new TrendDataPoint(d, byDate.getOrDefault(d, BigDecimal.ZERO)));
        }

        // Use the most recent personal cache's cachedAt for the trend timestamp
        OffsetDateTime cachedAt = personalStatsCacheRepository.findByUserId(userId)
                .map(PersonalStatsCache::getCachedAt)
                .orElse(OffsetDateTime.now(ZoneOffset.UTC));

        return new TrendResponse(data, cachedAt);
    }

    // -------------------------------------------------------------------------
    // GET /statistics/global
    // -------------------------------------------------------------------------

    /**
     * Returns anonymised global statistics. The response contains no user IDs,
     * email addresses, or any other PII.
     *
     * @return global stats response
     * @throws ResponseStatusException 404 if the global cache has not been populated yet
     */
    @Transactional(readOnly = true)
    public GlobalStatsResponse getGlobalStats() {
        GlobalStatsCache cache = globalStatsCacheRepository.findFirstByOrderByCachedAtDesc()
                .orElseGet(() -> {
                    log.info("No global stats cache present, triggering on-demand refresh");
                    refreshService.refreshGlobalStats();
                    return globalStatsCacheRepository.findFirstByOrderByCachedAtDesc()
                            .orElseThrow(() -> new ResponseStatusException(
                                    HttpStatus.NOT_FOUND,
                                    "No global statistics available yet."));
                });

        return mapToGlobalStatsResponse(cache);
    }

    // -------------------------------------------------------------------------
    // Mapping helpers
    // -------------------------------------------------------------------------

    private PersonalStatsResponse mapToPersonalStatsResponse(PersonalStatsCache cache) {
        List<DayOfWeekStat> byDayOfWeek = deserializeByDayOfWeek(cache.getByDayOfWeek());
        return new PersonalStatsResponse(
                cache.getTotalEntries(),
                cache.getTotalVolumeMl(),
                cache.getTotalStandardDrinks(),
                cache.getAvgDrinksPerDay30d(),
                byDayOfWeek,
                cache.getCachedAt());
    }

    private GlobalStatsResponse mapToGlobalStatsResponse(GlobalStatsCache cache) {
        List<String> topBeerNames = deserializeTopBeerNames(cache.getTopBeerNames());
        // GlobalStatsResponse intentionally contains no userId, email, or other PII
        return new GlobalStatsResponse(
                cache.getActiveUsers(),
                cache.getGlobalAvgDrinksPerDay(),
                topBeerNames,
                cache.getCachedAt());
    }

    /**
     * Computes personal stats from daily_trend_cache for the given date range.
     * This is used when the caller specifies from/to query parameters.
     */
    private PersonalStatsResponse computeScopedPersonalStats(
            UUID userId, LocalDate from, LocalDate to, OffsetDateTime cachedAt) {

        LocalDate effectiveFrom = from != null ? from : LocalDate.of(2000, 1, 1);
        LocalDate effectiveTo = to != null ? to : LocalDate.now(ZoneOffset.UTC);

        List<DailyTrendCache> trend = dailyTrendCacheRepository
                .findByUserIdAndTrendDateBetween(userId, effectiveFrom, effectiveTo);

        BigDecimal totalStandardDrinks = trend.stream()
                .map(t -> t.getStandardDrinks() != null ? t.getStandardDrinks() : BigDecimal.ZERO)
                .reduce(BigDecimal.ZERO, BigDecimal::add);

        long windowDays = effectiveFrom.until(effectiveTo).getDays() + 1;
        BigDecimal avgDrinksPerDay = windowDays > 0
                ? totalStandardDrinks.divide(BigDecimal.valueOf(windowDays), 2, RoundingMode.HALF_UP)
                : BigDecimal.ZERO;

        List<DayOfWeekStat> byDayOfWeek = computeByDayOfWeekFromTrend(trend);

        // totalEntries and totalVolumeMl are not available from daily trend cache alone
        return new PersonalStatsResponse(
                null,   // totalEntries not available for scoped queries
                null,   // totalVolumeMl not available for scoped queries
                totalStandardDrinks,
                avgDrinksPerDay,
                byDayOfWeek,
                cachedAt);
    }

    /**
     * Computes a Mon–Sun average breakdown from a list of daily trend entries.
     */
    private List<DayOfWeekStat> computeByDayOfWeekFromTrend(List<DailyTrendCache> trend) {
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
                    : values.stream().reduce(BigDecimal.ZERO, BigDecimal::add)
                             .divide(BigDecimal.valueOf(values.size()), 2, RoundingMode.HALF_UP);
            String displayName = dow.name().charAt(0) + dow.name().substring(1).toLowerCase();
            stats.add(new DayOfWeekStat(displayName, avg));
        }
        return stats;
    }

    private List<DayOfWeekStat> deserializeByDayOfWeek(String json) {
        if (json == null || json.isBlank() || "null".equals(json)) {
            return emptyByDayOfWeek();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<DayOfWeekStat>>() {});
        } catch (Exception ex) {
            log.warn("Failed to deserialise byDayOfWeek JSON: {}", ex.getMessage());
            return emptyByDayOfWeek();
        }
    }

    private List<String> deserializeTopBeerNames(String json) {
        if (json == null || json.isBlank() || "null".equals(json)) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<String>>() {});
        } catch (Exception ex) {
            log.warn("Failed to deserialise topBeerNames JSON: {}", ex.getMessage());
            return List.of();
        }
    }

    private List<DayOfWeekStat> emptyByDayOfWeek() {
        DayOfWeek[] ordered = {
            DayOfWeek.MONDAY, DayOfWeek.TUESDAY, DayOfWeek.WEDNESDAY,
            DayOfWeek.THURSDAY, DayOfWeek.FRIDAY, DayOfWeek.SATURDAY, DayOfWeek.SUNDAY
        };
        List<DayOfWeekStat> result = new ArrayList<>();
        for (DayOfWeek dow : ordered) {
            String displayName = dow.name().charAt(0) + dow.name().substring(1).toLowerCase();
            result.add(new DayOfWeekStat(displayName, BigDecimal.ZERO));
        }
        return result;
    }
}
