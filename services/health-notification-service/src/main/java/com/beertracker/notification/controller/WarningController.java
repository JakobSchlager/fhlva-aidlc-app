package com.beertracker.notification.controller;

import com.beertracker.notification.dto.PagedResponse;
import com.beertracker.notification.dto.WarningResponse;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.service.NotificationService;
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

    private final NotificationService notificationService;

    public WarningController(NotificationService notificationService) {
        this.notificationService = notificationService;
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
