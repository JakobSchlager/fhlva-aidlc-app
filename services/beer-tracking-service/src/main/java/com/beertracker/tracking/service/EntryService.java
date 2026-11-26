package com.beertracker.tracking.service;

import com.beertracker.tracking.dto.CreateEntryRequest;
import com.beertracker.tracking.dto.EntryResponse;
import com.beertracker.tracking.dto.PagedResponse;
import com.beertracker.tracking.dto.SummaryResponse;
import com.beertracker.tracking.entity.Entry;
import com.beertracker.tracking.repository.EntryRepository;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

@Service
@Transactional
public class EntryService {

    private static final Logger log = LoggerFactory.getLogger(EntryService.class);

    private final EntryRepository entryRepository;

    /**
     * Feature flag FEATURE_ENTRY_DAY_TOTALS (off by default): the entry list shows, per entry, its
     * standard drinks and the user's total for that day (the frontend's "Std. drinks" column).
     * The day total is looked up per listed entry, one query each, so a page of 20 entries costs
     * 21 queries instead of 1, and the cost grows with the page size.
     */
    @Value("${FEATURE_ENTRY_DAY_TOTALS:false}")
    private boolean entryDayTotals;

    public EntryService(EntryRepository entryRepository) {
        this.entryRepository = entryRepository;
    }

    @PostConstruct
    void logFeatureFlags() {
        log.info("Feature ENTRY_DAY_TOTALS {}", entryDayTotals ? "ON" : "off");
    }

    public EntryResponse create(UUID userId, CreateEntryRequest request) {
        Entry entry = new Entry();
        entry.setUserId(userId);
        entry.setBeerName(request.beerName());
        entry.setVolumeMl(request.volumeMl());
        entry.setAbv(request.abv());
        entry.setTimestamp(request.timestamp() != null ? request.timestamp() : Instant.now());
        return toResponse(entryRepository.save(entry));
    }

    @Transactional(readOnly = true)
    public PagedResponse<EntryResponse> list(UUID userId, int page, int size, Instant from, Instant to) {
        Pageable pageable = PageRequest.of(page, size, Sort.by(Sort.Direction.DESC, "timestamp"));
        Page<Entry> result;
        if (from != null && to != null) {
            result = entryRepository.findByUserIdAndTimestampBetween(userId, from, to, pageable);
        } else if (from != null) {
            result = entryRepository.findByUserIdAndTimestampBetween(userId, from, Instant.ofEpochMilli(Long.MAX_VALUE / 2), pageable);
        } else if (to != null) {
            result = entryRepository.findByUserIdAndTimestampBetween(userId, Instant.EPOCH, to, pageable);
        } else {
            result = entryRepository.findByUserId(userId, pageable);
        }
        return new PagedResponse<>(
                result.getContent().stream()
                        .map(e -> entryDayTotals ? toResponseWithDayTotal(e) : toResponse(e))
                        .toList(),
                page,
                size,
                result.getTotalElements()
        );
    }

    public EntryResponse update(UUID userId, UUID entryId, CreateEntryRequest request) {
        Entry entry = entryRepository.findById(entryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Entry not found"));
        if (!entry.getUserId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not the owner of this entry");
        }
        entry.setBeerName(request.beerName());
        entry.setVolumeMl(request.volumeMl());
        entry.setAbv(request.abv());
        if (request.timestamp() != null) {
            entry.setTimestamp(request.timestamp());
        }
        return toResponse(entryRepository.save(entry));
    }

    public void delete(UUID userId, UUID entryId) {
        Entry entry = entryRepository.findById(entryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Entry not found"));
        if (!entry.getUserId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "Not the owner of this entry");
        }
        entryRepository.delete(entry);
    }

    @Transactional(readOnly = true)
    public List<UUID> listDistinctUserIds() {
        return entryRepository.findDistinctUserIds();
    }

    @Transactional(readOnly = true)
    public SummaryResponse getSummary(UUID userId, Instant from, Instant to) {
        List<Entry> entries = entryRepository.findByUserIdAndTimestampBetween(userId, from, to);
        long totalVolumeMl = entries.stream()
                .mapToLong(Entry::getVolumeMl)
                .sum();
        BigDecimal totalStandardDrinks = sumStandardDrinks(entries);
        return new SummaryResponse(userId, entries.size(), totalVolumeMl, totalStandardDrinks);
    }

    private EntryResponse toResponse(Entry entry) {
        return new EntryResponse(
                entry.getId(),
                entry.getUserId(),
                entry.getBeerName(),
                entry.getVolumeMl(),
                entry.getAbv(),
                entry.getTimestamp(),
                null,
                null
        );
    }

    private EntryResponse toResponseWithDayTotal(Entry entry) {
        Instant dayStart = entry.getTimestamp().atZone(ZoneOffset.UTC).truncatedTo(ChronoUnit.DAYS).toInstant();
        Instant dayEnd = dayStart.plus(1, ChronoUnit.DAYS).minusNanos(1);
        // One query per listed entry (the "N" in N+1).
        List<Entry> sameDay = entryRepository.findByUserIdAndTimestampBetween(entry.getUserId(), dayStart, dayEnd);
        return new EntryResponse(
                entry.getId(),
                entry.getUserId(),
                entry.getBeerName(),
                entry.getVolumeMl(),
                entry.getAbv(),
                entry.getTimestamp(),
                sumStandardDrinks(List.of(entry)),
                sumStandardDrinks(sameDay)
        );
    }

    private static BigDecimal sumStandardDrinks(List<Entry> entries) {
        return entries.stream()
                .map(e -> BigDecimal.valueOf(e.getVolumeMl())
                        .multiply(e.getAbv())
                        .divide(BigDecimal.valueOf(1000), 10, RoundingMode.HALF_UP))
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .setScale(2, RoundingMode.HALF_UP);
    }
}
