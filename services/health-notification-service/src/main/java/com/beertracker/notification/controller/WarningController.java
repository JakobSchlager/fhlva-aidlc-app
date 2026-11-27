package com.beertracker.notification.controller;

import com.beertracker.notification.dto.PagedResponse;
import com.beertracker.notification.dto.WarningResponse;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.scheduler.ConsumptionEvaluationScheduler;
import com.beertracker.notification.service.NotificationService;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/notifications/warnings")
public class WarningController {

    private static final Logger log = LoggerFactory.getLogger(WarningController.class);

    private final NotificationService notificationService;
    private final ConsumptionEvaluationScheduler evaluator;

    /**
     * Feature flag FEATURE_LIVE_WARNINGS (off by default): warnings are always current. Without it,
     * a new warning appears only after the next scheduler run (every 5 minutes). With it, every
     * GET /notifications/warnings first evaluates the user live (7 calls to the tracking service
     * plus database writes) and then lists the warnings.
     */
    @Value("${FEATURE_LIVE_WARNINGS:false}")
    private boolean liveWarnings;

    public WarningController(NotificationService notificationService,
                             ConsumptionEvaluationScheduler evaluator) {
        this.notificationService = notificationService;
        this.evaluator = evaluator;
    }

    @PostConstruct
    void logFeatureFlags() {
        log.info("Feature LIVE_WARNINGS {}", liveWarnings ? "ON" : "off");
    }

    /**
     * GET /notifications/warnings?status=ACTIVE|RESOLVED|ACKNOWLEDGED&page=0&size=20
     * Returns a paginated list of warnings for the authenticated user.
     */
    @GetMapping
    public ResponseEntity<PagedResponse<WarningResponse>> getWarnings(
            @AuthenticationPrincipal Jwt jwt,
            @RequestParam(required = false) WarningStatus status,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {

        UUID userId = extractUserId(jwt);
        if (liveWarnings) {
            evaluator.evaluateUserLive(userId);
        }
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "triggeredAt"));
        PagedResponse<WarningResponse> response = notificationService.getWarnings(userId, status, pageable);
        return ResponseEntity.ok(response);
    }

    /**
     * POST /notifications/warnings/{id}/acknowledge
     * Acknowledges a warning owned by the authenticated user.
     */
    @PostMapping("/{id}/acknowledge")
    public ResponseEntity<WarningResponse> acknowledge(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID id) {

        UUID userId = extractUserId(jwt);
        WarningResponse response = notificationService.acknowledge(id, userId);
        return ResponseEntity.ok(response);
    }

    private UUID extractUserId(Jwt jwt) {
        // The subject claim ("sub") holds the user's UUID from the identity provider.
        String subject = jwt.getSubject();
        return UUID.fromString(subject);
    }
}
