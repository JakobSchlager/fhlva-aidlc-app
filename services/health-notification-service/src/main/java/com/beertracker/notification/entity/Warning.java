package com.beertracker.notification.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "warnings")
public class Warning {

    public enum WarningType {
        DAILY_EXCEEDED,
        WEEKLY_EXCEEDED
    }

    public enum WarningStatus {
        ACTIVE,
        RESOLVED,
        ACKNOWLEDGED
    }

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(nullable = false, updatable = false)
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 50)
    private WarningType type;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 50)
    private WarningStatus status = WarningStatus.ACTIVE;

    @Column(name = "triggered_at", nullable = false)
    private OffsetDateTime triggeredAt = OffsetDateTime.now();

    @Column(name = "resolved_at")
    private OffsetDateTime resolvedAt;

    @Column(name = "acknowledged_at")
    private OffsetDateTime acknowledgedAt;

    @Column(name = "threshold", nullable = false, precision = 5, scale = 2)
    private BigDecimal threshold;

    // ---------- constructors ----------

    protected Warning() {
    }

    public Warning(UUID userId, WarningType type, BigDecimal threshold) {
        this.userId = userId;
        this.type = type;
        this.threshold = threshold;
        this.status = WarningStatus.ACTIVE;
        this.triggeredAt = OffsetDateTime.now();
    }

    // ---------- getters & setters ----------

    public UUID getId() {
        return id;
    }

    public UUID getUserId() {
        return userId;
    }

    public void setUserId(UUID userId) {
        this.userId = userId;
    }

    public WarningType getType() {
        return type;
    }

    public void setType(WarningType type) {
        this.type = type;
    }

    public WarningStatus getStatus() {
        return status;
    }

    public void setStatus(WarningStatus status) {
        this.status = status;
    }

    public OffsetDateTime getTriggeredAt() {
        return triggeredAt;
    }

    public void setTriggeredAt(OffsetDateTime triggeredAt) {
        this.triggeredAt = triggeredAt;
    }

    public OffsetDateTime getResolvedAt() {
        return resolvedAt;
    }

    public void setResolvedAt(OffsetDateTime resolvedAt) {
        this.resolvedAt = resolvedAt;
    }

    public OffsetDateTime getAcknowledgedAt() {
        return acknowledgedAt;
    }

    public void setAcknowledgedAt(OffsetDateTime acknowledgedAt) {
        this.acknowledgedAt = acknowledgedAt;
    }

    public BigDecimal getThreshold() {
        return threshold;
    }

    public void setThreshold(BigDecimal threshold) {
        this.threshold = threshold;
    }
}
