package com.beertracker.notification.scheduler;

import com.beertracker.notification.repository.WarningRepository;
import com.beertracker.notification.service.NotificationService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Component
public class ConsumptionEvaluationScheduler {

    private static final Logger log = LoggerFactory.getLogger(ConsumptionEvaluationScheduler.class);

    private final WarningRepository warningRepository;
    private final NotificationService notificationService;
    private final RestTemplate restTemplate;

    @Value("${app.tracking.internalUrl}")
    private String trackingBaseUrl;

    @Value("${app.tracking.internalApiKey}")
    private String internalApiKey;

    public ConsumptionEvaluationScheduler(
            WarningRepository warningRepository,
            NotificationService notificationService,
            RestTemplate restTemplate) {
        this.warningRepository = warningRepository;
        this.notificationService = notificationService;
        this.restTemplate = restTemplate;
    }

    @Scheduled(fixedDelayString = "${app.scheduler.evaluationDelayMs:300000}")
    public void evaluateConsumption() {
        log.info("Consumption evaluation scheduler started");
        List<UUID> userIds = resolveUserIds();

        for (UUID userId : userIds) {
            try {
                evaluateUser(userId);
            } catch (Exception e) {
                log.warn("Failed to evaluate consumption for user {}: {}", userId, e.getMessage());
            }
        }

        log.info("Consumption evaluation scheduler completed for {} users", userIds.size());
    }

    /**
     * Collect all user IDs that need evaluation.
     * Starts from users already known in the warnings table, then merges any
     * users returned by the tracking service's user-list endpoint.
     */
    private List<UUID> resolveUserIds() {
        List<UUID> known = warningRepository.findDistinctUserIds();
        List<UUID> fromTracking = fetchUserIdsFromTracking();

        // Merge: add tracking users not already in the list
        List<UUID> merged = new ArrayList<>(known);
        for (UUID uid : fromTracking) {
            if (!merged.contains(uid)) {
                merged.add(uid);
            }
        }
        return merged;
    }

    @SuppressWarnings("unchecked")
    private List<UUID> fetchUserIdsFromTracking() {
        try {
            String url = trackingBaseUrl + "/internal/tracking/users";
            HttpHeaders headers = buildInternalHeaders();
            ResponseEntity<List> response = restTemplate.exchange(
                    url, HttpMethod.GET, new HttpEntity<>(headers), List.class);

            if (response.getBody() == null) {
                return List.of();
            }
            return response.getBody().stream()
                    .map(id -> UUID.fromString(id.toString()))
                    .toList();
        } catch (Exception e) {
            log.warn("Could not fetch user list from tracking service: {}", e.getMessage());
            return List.of();
        }
    }

    @SuppressWarnings("unchecked")
    private void evaluateUser(UUID userId) {
        double dailyDrinks = 0.0;
        double weeklyDrinks = 0.0;

        try {
            LocalDate today = LocalDate.now(ZoneOffset.UTC);
            LocalDate weekStart = today.minusDays(6);
            HttpHeaders headers = buildInternalHeaders();

            String dailyUrl = UriComponentsBuilder
                    .fromHttpUrl(trackingBaseUrl + "/internal/tracking/summary")
                    .queryParam("userId", userId)
                    .queryParam("from", today)
                    .queryParam("to", today)
                    .toUriString();
            ResponseEntity<Map> dailyResp = restTemplate.exchange(
                    dailyUrl, HttpMethod.GET, new HttpEntity<>(headers), Map.class);
            if (dailyResp.getBody() != null) {
                dailyDrinks = toDouble(dailyResp.getBody().get("totalStandardDrinks"));
            }

            String weeklyUrl = UriComponentsBuilder
                    .fromHttpUrl(trackingBaseUrl + "/internal/tracking/summary")
                    .queryParam("userId", userId)
                    .queryParam("from", weekStart)
                    .queryParam("to", today)
                    .toUriString();
            ResponseEntity<Map> weeklyResp = restTemplate.exchange(
                    weeklyUrl, HttpMethod.GET, new HttpEntity<>(headers), Map.class);
            if (weeklyResp.getBody() != null) {
                weeklyDrinks = toDouble(weeklyResp.getBody().get("totalStandardDrinks"));
            }
        } catch (Exception e) {
            log.warn("Could not fetch summary for user {}: {}", userId, e.getMessage());
        }

        notificationService.evaluateUser(userId, dailyDrinks, weeklyDrinks);
    }

    private HttpHeaders buildInternalHeaders() {
        HttpHeaders headers = new HttpHeaders();
        if (internalApiKey != null && !internalApiKey.isBlank()) {
            headers.set("X-Internal-Key", internalApiKey);
        }
        return headers;
    }

    private double toDouble(Object value) {
        if (value == null) {
            return 0.0;
        }
        if (value instanceof Number n) {
            return n.doubleValue();
        }
        try {
            return Double.parseDouble(value.toString());
        } catch (NumberFormatException e) {
            return 0.0;
        }
    }
}
