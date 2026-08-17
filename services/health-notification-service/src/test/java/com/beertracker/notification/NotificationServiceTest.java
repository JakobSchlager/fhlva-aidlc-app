package com.beertracker.notification;

import com.beertracker.notification.entity.Warning;
import com.beertracker.notification.entity.Warning.WarningStatus;
import com.beertracker.notification.entity.Warning.WarningType;
import com.beertracker.notification.repository.WarningRepository;
import com.beertracker.notification.service.NotificationService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.http.HttpStatus.FORBIDDEN;
import static org.springframework.http.HttpStatus.NOT_FOUND;

@ExtendWith(MockitoExtension.class)
class NotificationServiceTest {

    @Mock
    private WarningRepository warningRepository;

    @InjectMocks
    private NotificationService notificationService;

    private static final UUID USER_ID = UUID.randomUUID();
    private static final UUID OTHER_USER_ID = UUID.randomUUID();
    private static final double DAILY_THRESHOLD = 2.0;
    private static final double WEEKLY_THRESHOLD = 14.0;

    @BeforeEach
    void setUp() {
        ReflectionTestUtils.setField(notificationService, "thresholdDailyDrinks", DAILY_THRESHOLD);
        ReflectionTestUtils.setField(notificationService, "thresholdWeeklyDrinks", WEEKLY_THRESHOLD);
    }

    // -----------------------------------------------------------------------
    // evaluateUser — daily exceeded
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("evaluateUser: daily drinks exceeded → creates DAILY_EXCEEDED warning")
    void evaluateUser_dailyExceeded_createsWarning() {
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.DAILY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.WEEKLY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);
        when(warningRepository.save(any(Warning.class))).thenAnswer(inv -> inv.getArgument(0));

        notificationService.evaluateUser(USER_ID, 3.0, 5.0); // daily > 2, weekly ok

        ArgumentCaptor<Warning> captor = ArgumentCaptor.forClass(Warning.class);
        verify(warningRepository, times(1)).save(captor.capture());

        Warning saved = captor.getValue();
        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getType()).isEqualTo(WarningType.DAILY_EXCEEDED);
        assertThat(saved.getStatus()).isEqualTo(WarningStatus.ACTIVE);
        assertThat(saved.getThreshold()).isEqualByComparingTo(BigDecimal.valueOf(DAILY_THRESHOLD));
    }

    // -----------------------------------------------------------------------
    // evaluateUser — weekly exceeded
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("evaluateUser: weekly drinks exceeded → creates WEEKLY_EXCEEDED warning")
    void evaluateUser_weeklyExceeded_createsWarning() {
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.DAILY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.WEEKLY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);
        when(warningRepository.save(any(Warning.class))).thenAnswer(inv -> inv.getArgument(0));

        notificationService.evaluateUser(USER_ID, 1.0, 15.0); // daily ok, weekly > 14

        ArgumentCaptor<Warning> captor = ArgumentCaptor.forClass(Warning.class);
        verify(warningRepository, times(1)).save(captor.capture());

        Warning saved = captor.getValue();
        assertThat(saved.getType()).isEqualTo(WarningType.WEEKLY_EXCEEDED);
        assertThat(saved.getThreshold()).isEqualByComparingTo(BigDecimal.valueOf(WEEKLY_THRESHOLD));
    }

    // -----------------------------------------------------------------------
    // evaluateUser — below threshold resolves existing warning
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("evaluateUser: consumption drops below threshold → resolves ACTIVE warning")
    void evaluateUser_belowThreshold_resolvesExistingWarning() {
        Warning existingWarning = new Warning(USER_ID, WarningType.DAILY_EXCEEDED, BigDecimal.valueOf(DAILY_THRESHOLD));

        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.DAILY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(true);
        when(warningRepository.findByUserIdAndTypeAndStatus(USER_ID, WarningType.DAILY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(Optional.of(existingWarning));
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.WEEKLY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);
        when(warningRepository.save(any(Warning.class))).thenAnswer(inv -> inv.getArgument(0));

        notificationService.evaluateUser(USER_ID, 1.0, 5.0); // daily now ok

        assertThat(existingWarning.getStatus()).isEqualTo(WarningStatus.RESOLVED);
        assertThat(existingWarning.getResolvedAt()).isNotNull();
        verify(warningRepository).save(existingWarning);
    }

    // -----------------------------------------------------------------------
    // evaluateUser — no duplicate warning created
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("evaluateUser: ACTIVE warning already exists → no duplicate created")
    void evaluateUser_activeWarningAlreadyExists_noDuplicateCreated() {
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.DAILY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(true); // already active
        when(warningRepository.existsByUserIdAndTypeAndStatus(USER_ID, WarningType.WEEKLY_EXCEEDED, WarningStatus.ACTIVE))
                .thenReturn(false);

        notificationService.evaluateUser(USER_ID, 5.0, 5.0); // both exceeded but daily already tracked

        // save should never be called for DAILY_EXCEEDED since it already exists
        verify(warningRepository, never()).save(any(Warning.class));
    }

    // -----------------------------------------------------------------------
    // acknowledge — own warning
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("acknowledge: own warning → sets status ACKNOWLEDGED and returns response")
    void acknowledge_ownWarning_succeeds() {
        UUID warningId = UUID.randomUUID();
        Warning warning = new Warning(USER_ID, WarningType.DAILY_EXCEEDED, BigDecimal.valueOf(DAILY_THRESHOLD));
        ReflectionTestUtils.setField(warning, "id", warningId);

        when(warningRepository.findById(warningId)).thenReturn(Optional.of(warning));
        when(warningRepository.save(any(Warning.class))).thenAnswer(inv -> inv.getArgument(0));

        var response = notificationService.acknowledge(warningId, USER_ID);

        assertThat(response.status()).isEqualTo(WarningStatus.ACKNOWLEDGED);
        assertThat(warning.getAcknowledgedAt()).isNotNull();
        verify(warningRepository).save(warning);
    }

    // -----------------------------------------------------------------------
    // acknowledge — other user's warning → 403
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("acknowledge: warning belongs to another user → throws 403 FORBIDDEN")
    void acknowledge_otherUsersWarning_throwsForbidden() {
        UUID warningId = UUID.randomUUID();
        Warning warning = new Warning(OTHER_USER_ID, WarningType.DAILY_EXCEEDED, BigDecimal.valueOf(DAILY_THRESHOLD));
        ReflectionTestUtils.setField(warning, "id", warningId);

        when(warningRepository.findById(warningId)).thenReturn(Optional.of(warning));

        assertThatThrownBy(() -> notificationService.acknowledge(warningId, USER_ID))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode()).isEqualTo(FORBIDDEN));

        verify(warningRepository, never()).save(any());
    }

    // -----------------------------------------------------------------------
    // acknowledge — warning not found → 404
    // -----------------------------------------------------------------------

    @Test
    @DisplayName("acknowledge: warning not found → throws 404 NOT_FOUND")
    void acknowledge_warningNotFound_throwsNotFound() {
        UUID warningId = UUID.randomUUID();
        when(warningRepository.findById(warningId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> notificationService.acknowledge(warningId, USER_ID))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode()).isEqualTo(NOT_FOUND));
    }
}
