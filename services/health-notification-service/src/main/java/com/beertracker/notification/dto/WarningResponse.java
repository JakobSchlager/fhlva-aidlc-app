package com.beertracker.notification.dto;

import com.beertracker.notification.entity.Warning;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.entity.Warning.WarningType;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

public record WarningResponse(
        UUID id,
        UUID userId,
        WarningType type,
        WarningStatus status,
        OffsetDateTime triggeredAt,
        OffsetDateTime resolvedAt,
        OffsetDateTime acknowledgedAt,
        BigDecimal threshold
) {
    public static WarningResponse from(Warning warning) {
        return new WarningResponse(
                warning.getId(),
                warning.getUserId(),
                warning.getType(),
                warning.getStatus(),
                warning.getTriggeredAt(),
                warning.getResolvedAt(),
                warning.getAcknowledgedAt(),
                warning.getThreshold()
        );
    }
}
