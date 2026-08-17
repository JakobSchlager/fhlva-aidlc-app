package com.beertracker.statistics.service;

import com.beertracker.statistics.dto.TrackingInternalSummaryResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.time.LocalDate;
import java.util.Optional;
import java.util.UUID;

/**
 * HTTP client for the beer-tracking-service internal API.
 * All calls use the {@code X-Internal-Key} header for service-to-service auth.
 */
@Slf4j
@Component
public class TrackingServiceClient {

    private static final String INTERNAL_KEY_HEADER = "X-Internal-Key";

    private final RestTemplate restTemplate;
    private final String baseUrl;
    private final String internalApiKey;

    public TrackingServiceClient(
            RestTemplate restTemplate,
            @Value("${app.tracking.internalUrl}") String baseUrl,
            @Value("${app.tracking.internalApiKey}") String internalApiKey) {
        this.restTemplate = restTemplate;
        this.baseUrl = baseUrl;
        this.internalApiKey = internalApiKey;
    }

    /**
     * Calls {@code GET /internal/tracking/summary?userId=&from=&to=} on the tracking service.
     *
     * @param userId the user whose entries are summarised
     * @param from   start date (inclusive)
     * @param to     end date (inclusive)
     * @return the summary response, or empty if the call fails or returns no body
     */
    public Optional<TrackingInternalSummaryResponse> getSummary(UUID userId, LocalDate from, LocalDate to) {
        String url = UriComponentsBuilder
                .fromHttpUrl(baseUrl + "/internal/tracking/summary")
                .queryParam("userId", userId)
                .queryParam("from", from)
                .queryParam("to", to)
                .toUriString();

        try {
            ResponseEntity<TrackingInternalSummaryResponse> response = restTemplate.exchange(
                    url,
                    HttpMethod.GET,
                    buildAuthEntity(),
                    TrackingInternalSummaryResponse.class);
            return Optional.ofNullable(response.getBody());
        } catch (Exception ex) {
            log.warn("Failed to call tracking service summary for userId={}: {}", userId, ex.getMessage());
            return Optional.empty();
        }
    }

    /**
     * Returns the standard drinks consumed by {@code userId} on a single calendar day.
     *
     * @param userId the target user
     * @param date   the calendar day to query
     * @return daily standard drinks, or empty if the call fails
     */
    public Optional<TrackingInternalSummaryResponse> getDailySummary(UUID userId, LocalDate date) {
        return getSummary(userId, date, date);
    }

    // -------------------------------------------------------------------------

    private HttpEntity<Void> buildAuthEntity() {
        HttpHeaders headers = new HttpHeaders();
        headers.set(INTERNAL_KEY_HEADER, internalApiKey);
        return new HttpEntity<>(headers);
    }
}
