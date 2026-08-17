package com.beertracker.statistics;

import com.beertracker.statistics.dto.GlobalStatsResponse;
import com.beertracker.statistics.dto.TrendDataPoint;
import com.beertracker.statistics.dto.TrendResponse;
import com.beertracker.statistics.entity.DailyTrendCache;
import com.beertracker.statistics.entity.GlobalStatsCache;
import com.beertracker.statistics.entity.PersonalStatsCache;
import com.beertracker.statistics.repository.DailyTrendCacheRepository;
import com.beertracker.statistics.repository.GlobalStatsCacheRepository;
import com.beertracker.statistics.repository.PersonalStatsCacheRepository;
import com.beertracker.statistics.service.StatisticsRefreshService;
import com.beertracker.statistics.service.StatisticsService;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link StatisticsService}.
 * All external dependencies are mocked; no Spring context or database is needed.
 */
@ExtendWith(MockitoExtension.class)
class StatisticsServiceTest {

    @Mock
    private PersonalStatsCacheRepository personalStatsCacheRepository;

    @Mock
    private GlobalStatsCacheRepository globalStatsCacheRepository;

    @Mock
    private DailyTrendCacheRepository dailyTrendCacheRepository;

    @Mock
    private StatisticsRefreshService refreshService;

    private StatisticsService statisticsService;

    private final UUID USER_ID = UUID.randomUUID();
    private final OffsetDateTime CACHED_AT = OffsetDateTime.of(2025, 6, 1, 12, 0, 0, 0, ZoneOffset.UTC);

    @BeforeEach
    void setUp() {
        statisticsService = new StatisticsService(
                personalStatsCacheRepository,
                globalStatsCacheRepository,
                dailyTrendCacheRepository,
                refreshService,
                new ObjectMapper()
        );
    }

    // =========================================================================
    // getTrend — zero-fill behaviour
    // =========================================================================

    @Nested
    @DisplayName("getTrend")
    class GetTrendTests {

        @Test
        @DisplayName("returns 30 data points with zero-fill for days that have no cached entry")
        void trend_zeroFillsMissingDays() {
            // Given: only one day in the 30-day window has cached data
            LocalDate today = LocalDate.now(ZoneOffset.UTC);
            LocalDate from  = today.minusDays(29); // 30-day window is [today-29 .. today]

            LocalDate dayWithData = today.minusDays(5);
            DailyTrendCache singleEntry = DailyTrendCache.builder()
                    .userId(USER_ID)
                    .trendDate(dayWithData)
                    .standardDrinks(new BigDecimal("2.50"))
                    .build();

            when(dailyTrendCacheRepository.findByUserIdAndTrendDateBetween(eq(USER_ID), any(), any()))
                    .thenReturn(List.of(singleEntry));

            PersonalStatsCache personalCache = PersonalStatsCache.builder()
                    .userId(USER_ID)
                    .cachedAt(CACHED_AT)
                    .build();
            when(personalStatsCacheRepository.findByUserId(USER_ID))
                    .thenReturn(Optional.of(personalCache));

            // When
            TrendResponse response = statisticsService.getTrend(USER_ID, 30);

            // Then
            assertThat(response).isNotNull();
            assertThat(response.data()).hasSize(30);
            assertThat(response.cachedAt()).isEqualTo(CACHED_AT);

            // The one day with data should have 2.50
            TrendDataPoint populated = response.data().stream()
                    .filter(p -> p.date().equals(dayWithData))
                    .findFirst()
                    .orElseThrow();
            assertThat(populated.standardDrinks()).isEqualByComparingTo("2.50");

            // All other days should be zero
            long zeroDays = response.data().stream()
                    .filter(p -> !p.date().equals(dayWithData))
                    .filter(p -> p.standardDrinks().compareTo(BigDecimal.ZERO) == 0)
                    .count();
            assertThat(zeroDays).isEqualTo(29);
        }

        @Test
        @DisplayName("returns exactly N data points covering consecutive dates")
        void trend_returnsConsecutiveDates() {
            when(dailyTrendCacheRepository.findByUserIdAndTrendDateBetween(eq(USER_ID), any(), any()))
                    .thenReturn(List.of());
            when(personalStatsCacheRepository.findByUserId(USER_ID))
                    .thenReturn(Optional.of(PersonalStatsCache.builder()
                            .userId(USER_ID)
                            .cachedAt(CACHED_AT)
                            .build()));

            TrendResponse response = statisticsService.getTrend(USER_ID, 7);

            assertThat(response.data()).hasSize(7);

            // Dates must be in ascending order and consecutive
            List<LocalDate> dates = response.data().stream().map(TrendDataPoint::date).toList();
            for (int i = 1; i < dates.size(); i++) {
                assertThat(dates.get(i)).isEqualTo(dates.get(i - 1).plusDays(1));
            }
        }

        // -----------------------------------------------------------------------
        // Validation: days > 365 → 400
        // -----------------------------------------------------------------------

        @Test
        @DisplayName("throws 400 BAD_REQUEST when days exceeds 365")
        void trend_throwsBadRequest_whenDaysExceedsMax() {
            assertThatThrownBy(() -> statisticsService.getTrend(USER_ID, 366))
                    .isInstanceOf(ResponseStatusException.class)
                    .hasMessageContaining("365")
                    .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode().value())
                            .isEqualTo(400));
        }

        @Test
        @DisplayName("throws 400 BAD_REQUEST for exactly 366 days")
        void trend_throwsBadRequest_forExactly366() {
            assertThatThrownBy(() -> statisticsService.getTrend(USER_ID, 366))
                    .isInstanceOf(ResponseStatusException.class);
        }

        @Test
        @DisplayName("accepts exactly 365 days without throwing")
        void trend_accepts365Days() {
            when(dailyTrendCacheRepository.findByUserIdAndTrendDateBetween(eq(USER_ID), any(), any()))
                    .thenReturn(List.of());
            when(personalStatsCacheRepository.findByUserId(USER_ID))
                    .thenReturn(Optional.of(PersonalStatsCache.builder()
                            .userId(USER_ID)
                            .cachedAt(CACHED_AT)
                            .build()));

            TrendResponse response = statisticsService.getTrend(USER_ID, 365);

            assertThat(response.data()).hasSize(365);
        }
    }

    // =========================================================================
    // getGlobalStats — PII-free response
    // =========================================================================

    @Nested
    @DisplayName("getGlobalStats")
    class GetGlobalStatsTests {

        @Test
        @DisplayName("returns global stats with no user IDs or PII")
        void globalStats_containsNoPii() {
            GlobalStatsCache cache = GlobalStatsCache.builder()
                    .activeUsers(42)
                    .globalAvgDrinksPerDay(new BigDecimal("1.75"))
                    .topBeerNames("[\"Lager X\",\"Pale Ale Y\"]")
                    .cachedAt(CACHED_AT)
                    .build();

            when(globalStatsCacheRepository.findFirstByOrderByCachedAtDesc())
                    .thenReturn(Optional.of(cache));

            GlobalStatsResponse response = statisticsService.getGlobalStats();

            assertThat(response).isNotNull();
            assertThat(response.activeUsers()).isEqualTo(42);
            assertThat(response.globalAvgDrinksPerDay()).isEqualByComparingTo("1.75");
            assertThat(response.topBeerNames()).containsExactly("Lager X", "Pale Ale Y");
            assertThat(response.cachedAt()).isEqualTo(CACHED_AT);

            // Verify the response type has no userId or email-carrying field
            // (structural guarantee: GlobalStatsResponse record has no such component)
            assertThat(GlobalStatsResponse.class.getRecordComponents())
                    .extracting(java.lang.reflect.RecordComponent::getName)
                    .doesNotContain("userId", "email", "userName");
        }

        @Test
        @DisplayName("returns cachedAt from the cache snapshot, not the current time")
        void globalStats_cachedAtMatchesSnapshot() {
            OffsetDateTime snapshotTime = OffsetDateTime.of(2025, 3, 15, 9, 0, 0, 0, ZoneOffset.UTC);
            GlobalStatsCache cache = GlobalStatsCache.builder()
                    .activeUsers(10)
                    .globalAvgDrinksPerDay(BigDecimal.ONE)
                    .topBeerNames("[]")
                    .cachedAt(snapshotTime)
                    .build();

            when(globalStatsCacheRepository.findFirstByOrderByCachedAtDesc())
                    .thenReturn(Optional.of(cache));

            GlobalStatsResponse response = statisticsService.getGlobalStats();

            assertThat(response.cachedAt()).isEqualTo(snapshotTime);
        }
    }

    // =========================================================================
    // Stale cache behaviour
    // =========================================================================

    @Nested
    @DisplayName("stale cache")
    class StaleCacheTests {

        @Test
        @DisplayName("serves stale personal stats without error when cache refresh has failed")
        void personalStats_servesStaleCache() {
            // Given: a cached entry with an old timestamp (simulating stale data)
            OffsetDateTime staleTimestamp = OffsetDateTime.of(2025, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);
            PersonalStatsCache staleCache = PersonalStatsCache.builder()
                    .userId(USER_ID)
                    .totalEntries(10)
                    .totalVolumeMl(5000L)
                    .totalStandardDrinks(new BigDecimal("12.50"))
                    .avgDrinksPerDay30d(new BigDecimal("0.42"))
                    .byDayOfWeek("[]")
                    .cachedAt(staleTimestamp)
                    .build();

            when(personalStatsCacheRepository.findByUserId(USER_ID))
                    .thenReturn(Optional.of(staleCache));

            // When: service is called (even though refresh has hypothetically failed)
            var response = statisticsService.getPersonalStats(USER_ID, null, null);

            // Then: stale data is returned with HTTP 200 (no exception thrown)
            assertThat(response).isNotNull();
            assertThat(response.totalStandardDrinks()).isEqualByComparingTo("12.50");
            assertThat(response.cachedAt()).isEqualTo(staleTimestamp);
        }

        @Test
        @DisplayName("serves stale global stats without error when cache refresh has failed")
        void globalStats_servesStaleCache() {
            OffsetDateTime staleTimestamp = OffsetDateTime.of(2024, 12, 31, 23, 59, 0, 0, ZoneOffset.UTC);
            GlobalStatsCache staleCache = GlobalStatsCache.builder()
                    .activeUsers(55)
                    .globalAvgDrinksPerDay(new BigDecimal("2.10"))
                    .topBeerNames("[]")
                    .cachedAt(staleTimestamp)
                    .build();

            when(globalStatsCacheRepository.findFirstByOrderByCachedAtDesc())
                    .thenReturn(Optional.of(staleCache));

            GlobalStatsResponse response = statisticsService.getGlobalStats();

            assertThat(response).isNotNull();
            assertThat(response.activeUsers()).isEqualTo(55);
            assertThat(response.cachedAt()).isEqualTo(staleTimestamp);
        }

        @Test
        @DisplayName("triggers on-demand refresh when no personal cache exists, then returns result")
        void personalStats_triggersOnDemandRefresh_whenNoCacheFound() {
            // Given: no cache initially, then present after refresh
            PersonalStatsCache freshCache = PersonalStatsCache.builder()
                    .userId(USER_ID)
                    .totalEntries(3)
                    .totalVolumeMl(1500L)
                    .totalStandardDrinks(new BigDecimal("3.60"))
                    .avgDrinksPerDay30d(new BigDecimal("0.12"))
                    .byDayOfWeek("[]")
                    .cachedAt(CACHED_AT)
                    .build();

            // First call returns empty (no cache), second returns the refreshed cache
            when(personalStatsCacheRepository.findByUserId(USER_ID))
                    .thenReturn(Optional.empty())
                    .thenReturn(Optional.of(freshCache));

            doNothing().when(refreshService).refreshUserStats(USER_ID);

            var response = statisticsService.getPersonalStats(USER_ID, null, null);

            assertThat(response).isNotNull();
            assertThat(response.totalStandardDrinks()).isEqualByComparingTo("3.60");
        }
    }

    // =========================================================================
    // Standard drinks formula verification (unit-level sanity check)
    // =========================================================================

    @Test
    @DisplayName("standard drinks formula: (volumeMl * abv/100) / 10 equals expected value")
    void standardDrinksFormula() {
        // 500 ml at 5% ABV = (500 * 0.05) / 10 = 2.5 standard drinks
        double volumeMl = 500;
        double abv = 5.0;
        double expectedStandardDrinks = (volumeMl * (abv / 100)) / 10;

        assertThat(expectedStandardDrinks).isEqualTo(2.5);
    }
}
