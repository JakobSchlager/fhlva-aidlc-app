package com.beertracker.tracking;

import com.beertracker.tracking.dto.CreateEntryRequest;
import com.beertracker.tracking.dto.EntryResponse;
import com.beertracker.tracking.dto.PagedResponse;
import com.beertracker.tracking.dto.SummaryResponse;
import com.beertracker.tracking.entity.Entry;
import com.beertracker.tracking.repository.EntryRepository;
import com.beertracker.tracking.service.EntryService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EntryServiceTest {

    @Mock
    private EntryRepository entryRepository;

    @InjectMocks
    private EntryService entryService;

    @Test
    void createEntry_validRequest_savesAndReturnsEntry() {
        UUID userId = UUID.randomUUID();
        CreateEntryRequest request = new CreateEntryRequest("IPA", 500, new BigDecimal("5.0"), null);

        Entry saved = buildEntry(UUID.randomUUID(), userId, "IPA", 500, new BigDecimal("5.0"), Instant.now());
        when(entryRepository.save(any(Entry.class))).thenReturn(saved);

        EntryResponse response = entryService.create(userId, request);

        assertThat(response.beerName()).isEqualTo("IPA");
        assertThat(response.volumeMl()).isEqualTo(500);
        assertThat(response.abv()).isEqualByComparingTo(new BigDecimal("5.0"));
        assertThat(response.userId()).isEqualTo(userId);

        ArgumentCaptor<Entry> captor = ArgumentCaptor.forClass(Entry.class);
        verify(entryRepository).save(captor.capture());
        assertThat(captor.getValue().getBeerName()).isEqualTo("IPA");
        assertThat(captor.getValue().getVolumeMl()).isEqualTo(500);
    }

    @Test
    void createEntry_withZeroVolume_savesEntryAsProvided() {
        UUID userId = UUID.randomUUID();
        CreateEntryRequest request = new CreateEntryRequest("Water", 0, new BigDecimal("0.0"), null);

        Entry saved = buildEntry(UUID.randomUUID(), userId, "Water", 0, new BigDecimal("0.0"), Instant.now());
        when(entryRepository.save(any(Entry.class))).thenReturn(saved);

        EntryResponse response = entryService.create(userId, request);

        assertThat(response.volumeMl()).isZero();
        assertThat(response.abv()).isEqualByComparingTo(BigDecimal.ZERO);
    }

    @Test
    void createEntry_withExplicitTimestamp_usesProvidedTimestamp() {
        UUID userId = UUID.randomUUID();
        Instant explicitTime = Instant.parse("2024-06-15T18:00:00Z");
        CreateEntryRequest request = new CreateEntryRequest("Lager", 330, new BigDecimal("4.5"), explicitTime);

        Entry saved = buildEntry(UUID.randomUUID(), userId, "Lager", 330, new BigDecimal("4.5"), explicitTime);
        when(entryRepository.save(any(Entry.class))).thenReturn(saved);

        EntryResponse response = entryService.create(userId, request);

        assertThat(response.timestamp()).isEqualTo(explicitTime);
        ArgumentCaptor<Entry> captor = ArgumentCaptor.forClass(Entry.class);
        verify(entryRepository).save(captor.capture());
        assertThat(captor.getValue().getTimestamp()).isEqualTo(explicitTime);
    }

    @Test
    void listEntries_withoutDateFilter_callsFindByUserId() {
        UUID userId = UUID.randomUUID();
        Entry entry = buildEntry(UUID.randomUUID(), userId, "Stout", 400, new BigDecimal("6.0"), Instant.now());
        when(entryRepository.findByUserId(eq(userId), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(entry)));

        PagedResponse<EntryResponse> response = entryService.list(userId, 0, 20, null, null);

        assertThat(response.items()).hasSize(1);
        assertThat(response.page()).isZero();
        assertThat(response.pageSize()).isEqualTo(20);
        assertThat(response.totalCount()).isEqualTo(1);
        verify(entryRepository).findByUserId(eq(userId), any(Pageable.class));
    }

    @Test
    void listEntries_withDateFilter_callsFindByUserIdAndTimestampBetween() {
        UUID userId = UUID.randomUUID();
        Instant from = Instant.parse("2024-01-01T00:00:00Z");
        Instant to = Instant.parse("2024-01-31T00:00:00Z");
        Entry entry = buildEntry(UUID.randomUUID(), userId, "IPA", 500, new BigDecimal("5.0"),
                Instant.parse("2024-01-15T12:00:00Z"));
        when(entryRepository.findByUserIdAndTimestampBetween(eq(userId), eq(from), eq(to), any(Pageable.class)))
                .thenReturn(new PageImpl<>(List.of(entry)));

        PagedResponse<EntryResponse> response = entryService.list(userId, 0, 10, from, to);

        assertThat(response.items()).hasSize(1);
        assertThat(response.totalCount()).isEqualTo(1);
        verify(entryRepository).findByUserIdAndTimestampBetween(eq(userId), eq(from), eq(to), any(Pageable.class));
    }

    @Test
    void updateEntry_ownEntry_updatesAndReturnsEntry() {
        UUID userId = UUID.randomUUID();
        UUID entryId = UUID.randomUUID();
        Entry existing = buildEntry(entryId, userId, "Old IPA", 330, new BigDecimal("5.0"), Instant.now());
        CreateEntryRequest request = new CreateEntryRequest("New IPA", 500, new BigDecimal("6.0"), null);
        Entry updated = buildEntry(entryId, userId, "New IPA", 500, new BigDecimal("6.0"), existing.getTimestamp());

        when(entryRepository.findById(entryId)).thenReturn(Optional.of(existing));
        when(entryRepository.save(any(Entry.class))).thenReturn(updated);

        EntryResponse response = entryService.update(userId, entryId, request);

        assertThat(response.beerName()).isEqualTo("New IPA");
        assertThat(response.volumeMl()).isEqualTo(500);
        assertThat(response.abv()).isEqualByComparingTo(new BigDecimal("6.0"));
    }

    @Test
    void updateEntry_differentOwner_throwsForbidden() {
        UUID ownerId = UUID.randomUUID();
        UUID requesterId = UUID.randomUUID();
        UUID entryId = UUID.randomUUID();
        Entry existing = buildEntry(entryId, ownerId, "IPA", 500, new BigDecimal("5.0"), Instant.now());
        CreateEntryRequest request = new CreateEntryRequest("Lager", 330, new BigDecimal("4.0"), null);

        when(entryRepository.findById(entryId)).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> entryService.update(requesterId, entryId, request))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode())
                        .isEqualTo(HttpStatus.FORBIDDEN));
    }

    @Test
    void updateEntry_notFound_throwsNotFound() {
        UUID userId = UUID.randomUUID();
        UUID entryId = UUID.randomUUID();
        CreateEntryRequest request = new CreateEntryRequest("IPA", 500, new BigDecimal("5.0"), null);

        when(entryRepository.findById(entryId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> entryService.update(userId, entryId, request))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode())
                        .isEqualTo(HttpStatus.NOT_FOUND));
    }

    @Test
    void deleteEntry_ownEntry_deletesSuccessfully() {
        UUID userId = UUID.randomUUID();
        UUID entryId = UUID.randomUUID();
        Entry existing = buildEntry(entryId, userId, "IPA", 500, new BigDecimal("5.0"), Instant.now());

        when(entryRepository.findById(entryId)).thenReturn(Optional.of(existing));

        entryService.delete(userId, entryId);

        verify(entryRepository).delete(existing);
    }

    @Test
    void deleteEntry_differentOwner_throwsForbidden() {
        UUID ownerId = UUID.randomUUID();
        UUID requesterId = UUID.randomUUID();
        UUID entryId = UUID.randomUUID();
        Entry existing = buildEntry(entryId, ownerId, "IPA", 500, new BigDecimal("5.0"), Instant.now());

        when(entryRepository.findById(entryId)).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> entryService.delete(requesterId, entryId))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> assertThat(((ResponseStatusException) ex).getStatusCode())
                        .isEqualTo(HttpStatus.FORBIDDEN));
    }

    @Test
    void getSummary_calculatesStandardDrinksCorrectly() {
        UUID userId = UUID.randomUUID();
        Instant from = Instant.parse("2024-01-01T00:00:00Z");
        Instant to = Instant.parse("2024-02-01T00:00:00Z");

        // 500ml at 5% ABV => 500 * 5 / 1000 = 2.50 standard drinks
        Entry entry1 = buildEntry(UUID.randomUUID(), userId, "IPA", 500, new BigDecimal("5.0"),
                Instant.parse("2024-01-10T12:00:00Z"));
        // 330ml at 4% ABV => 330 * 4 / 1000 = 1.32 standard drinks
        Entry entry2 = buildEntry(UUID.randomUUID(), userId, "Lager", 330, new BigDecimal("4.0"),
                Instant.parse("2024-01-20T18:00:00Z"));

        when(entryRepository.findByUserIdAndTimestampBetween(userId, from, to))
                .thenReturn(List.of(entry1, entry2));

        SummaryResponse summary = entryService.getSummary(userId, from, to);

        assertThat(summary.userId()).isEqualTo(userId);
        assertThat(summary.totalVolumeMl()).isEqualTo(830L);
        assertThat(summary.totalStandardDrinks()).isEqualByComparingTo(new BigDecimal("3.82"));
    }

    @Test
    void getSummary_noEntries_returnsZero() {
        UUID userId = UUID.randomUUID();
        Instant from = Instant.parse("2024-01-01T00:00:00Z");
        Instant to = Instant.parse("2024-02-01T00:00:00Z");

        when(entryRepository.findByUserIdAndTimestampBetween(userId, from, to))
                .thenReturn(List.of());

        SummaryResponse summary = entryService.getSummary(userId, from, to);

        assertThat(summary.totalVolumeMl()).isZero();
        assertThat(summary.totalStandardDrinks()).isEqualByComparingTo(BigDecimal.ZERO);
    }

    private Entry buildEntry(UUID id, UUID userId, String beerName, int volumeMl, BigDecimal abv, Instant timestamp) {
        Entry entry = new Entry();
        entry.setId(id);
        entry.setUserId(userId);
        entry.setBeerName(beerName);
        entry.setVolumeMl(volumeMl);
        entry.setAbv(abv);
        entry.setTimestamp(timestamp);
        entry.setCreatedAt(Instant.now().truncatedTo(ChronoUnit.MILLIS));
        return entry;
    }
}
