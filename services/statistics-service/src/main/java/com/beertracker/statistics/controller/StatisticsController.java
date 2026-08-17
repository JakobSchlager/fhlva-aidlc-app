package com.beertracker.statistics.controller;

import com.beertracker.statistics.dto.GlobalStatsResponse;
import com.beertracker.statistics.dto.PersonalStatsResponse;
import com.beertracker.statistics.dto.TrendResponse;
import com.beertracker.statistics.security.JwtUserExtractor;
import com.beertracker.statistics.service.StatisticsService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.UUID;

/**
 * Exposes the three statistics endpoints:
 * <ul>
 *   <li>GET /statistics/me        — personal aggregate stats</li>
 *   <li>GET /statistics/me/trend  — daily standard-drink time series</li>
 *   <li>GET /statistics/global    — anonymised global stats</li>
 * </ul>
 * All endpoints require a valid Bearer JWT.
 */
@Slf4j
@RestController
@RequestMapping("/statistics")
@RequiredArgsConstructor
public class StatisticsController {

    private static final int DEFAULT_TREND_DAYS = 30;

    private final StatisticsService statisticsService;
    private final JwtUserExtractor jwtUserExtractor;

    /**
     * Returns personal aggregate statistics for the authenticated user.
     *
     * @param jwt  validated JWT injected by Spring Security
     * @param from optional ISO-8601 date to scope stats from (inclusive)
     * @param to   optional ISO-8601 date to scope stats to (inclusive)
     */
    @GetMapping("/me")
    public ResponseEntity<PersonalStatsResponse> getPersonalStats(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {

        UUID userId = jwtUserExtractor.extractUserId(jwt);
        log.debug("GET /statistics/me userId={} from={} to={}", userId, from, to);

        PersonalStatsResponse response = statisticsService.getPersonalStats(userId, from, to);
        return ResponseEntity.ok(response);
    }

    /**
     * Returns a daily standard-drink time series for the authenticated user.
     *
     * @param jwt  validated JWT injected by Spring Security
     * @param days number of past days to include (default 30, max 365)
     * @return 400 if {@code days > 365}
     */
    @GetMapping("/me/trend")
    public ResponseEntity<TrendResponse> getTrend(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(defaultValue = "30") int days) {

        UUID userId = jwtUserExtractor.extractUserId(jwt);
        log.debug("GET /statistics/me/trend userId={} days={}", userId, days);

        TrendResponse response = statisticsService.getTrend(userId, days);
        return ResponseEntity.ok(response);
    }

    /**
     * Returns anonymised global statistics across all users.
     * The response contains no user IDs, emails, or any other PII.
     *
     * @param jwt validated JWT injected by Spring Security
     */
    @GetMapping("/global")
    public ResponseEntity<GlobalStatsResponse> getGlobalStats(@AuthenticationPrincipal Jwt jwt) {
        log.debug("GET /statistics/global");
        GlobalStatsResponse response = statisticsService.getGlobalStats();
        return ResponseEntity.ok(response);
    }
}
