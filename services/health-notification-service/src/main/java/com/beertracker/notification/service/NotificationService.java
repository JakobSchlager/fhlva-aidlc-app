package com.beertracker.notification.service;

import com.beertracker.notification.dto.PagedResponse;
import com.beertracker.notification.dto.WarningResponse;
import com.beertracker.notification.entity.Warning;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.entity.Warning.WarningType;
import com.beertracker.notification.repository.WarningRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

@Service
public class NotificationService {

    private static final Logger log = LoggerFactory.getLogger(NotificationService.class);

    private final WarningRepository warningRepository;

    @Value("${app.notification.thresholdDailyDrinks}")
    private double thresholdDailyDrinks;

    @Value("${app.notification.thresholdWeeklyDrinks}")
    private double thresholdWeeklyDrinks;

    public NotificationService(WarningRepository warningRepository) {
        this.warningRepository = warningRepository;
    }

    /**
     * Evaluate consumption for a single user and create or resolve warnings accordingly.
     */
    @Transactional
    public void evaluateUser(UUID userId, double dailyDrinks, double weeklyDrinks) {
        evaluateThreshold(userId, WarningType.DAILY_EXCEEDED, dailyDrinks, thresholdDailyDrinks);
        evaluateThreshold(userId, WarningType.WEEKLY_EXCEEDED, weeklyDrinks, thresholdWeeklyDrinks);
    }

    private void evaluateThreshold(UUID userId, WarningType type, double current, double threshold) {
        boolean exceeded = current > threshold;
        boolean activeExists = warningRepository.existsByUserIdAndTypeAndStatus(userId, type, WarningStatus.ACTIVE);

        if (exceeded && !activeExists) {
            Warning warning = new Warning(userId, type, BigDecimal.valueOf(threshold));
            warningRepository.save(warning);
            log.info("Created {} warning for user {} (current={}, threshold={})", type, userId, current, threshold);

        } else if (!exceeded && activeExists) {
            warningRepository.findByUserIdAndTypeAndStatus(userId, type, WarningStatus.ACTIVE)
                    .ifPresent(w -> {
                        w.setStatus(WarningStatus.RESOLVED);
                        w.setResolvedAt(OffsetDateTime.now());
                        warningRepository.save(w);
                        log.info("Resolved {} warning for user {} (current={}, threshold={})", type, userId, current, threshold);
                    });
        }
    }

    /**
     * Return a paginated list of warnings for the authenticated user, optionally filtered by status.
     */
    @Transactional(readOnly = true)
    public PagedResponse<WarningResponse> getWarnings(UUID userId, WarningStatus status, Pageable pageable) {
        if (status != null) {
            return PagedResponse.from(
                    warningRepository.findByUserIdAndStatus(userId, status, pageable),
                    WarningResponse::from
            );
        }
        return PagedResponse.from(
                warningRepository.findByUserId(userId, pageable),
                WarningResponse::from
        );
    }

    /**
     * Acknowledge a warning. Verifies the warning belongs to the requesting user.
     */
    @Transactional
    public WarningResponse acknowledge(UUID warningId, UUID userId) {
        Warning warning = warningRepository.findById(warningId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Warning not found: " + warningId));

        if (!warning.getUserId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN,
                    "Warning does not belong to the requesting user");
        }

        if (warning.getStatus() == WarningStatus.ACKNOWLEDGED) {
            return WarningResponse.from(warning);
        }

        warning.setStatus(WarningStatus.ACKNOWLEDGED);
        warning.setAcknowledgedAt(OffsetDateTime.now());
        return WarningResponse.from(warningRepository.save(warning));
    }
}
