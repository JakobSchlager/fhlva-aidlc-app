package com.beertracker.tracking.service;

import com.beertracker.tracking.dto.CreateEntryRequest;
import com.beertracker.tracking.dto.EntryResponse;
import com.beertracker.tracking.dto.PagedResponse;
import com.beertracker.tracking.dto.SummaryResponse;
import com.beertracker.tracking.entity.Entry;
import com.beertracker.tracking.repository.EntryRepository;
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
import java.util.List;
import java.util.UUID;

@Service
@Transactional
public class EntryService {

    private final EntryRepository entryRepository;

    public EntryService(EntryRepository entryRepository) {
        this.entryRepository = entryRepository;
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
                result.getContent().stream().map(this::toResponse).toList(),
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
        BigDecimal totalStandardDrinks = entries.stream()
                .map(e -> BigDecimal.valueOf(e.getVolumeMl())
                        .multiply(e.getAbv())
                        .divide(BigDecimal.valueOf(1000), 10, RoundingMode.HALF_UP))
                .reduce(BigDecimal.ZERO, BigDecimal::add)
                .setScale(2, RoundingMode.HALF_UP);
        return new SummaryResponse(userId, entries.size(), totalVolumeMl, totalStandardDrinks);
    }

    private EntryResponse toResponse(Entry entry) {
        return new EntryResponse(
                entry.getId(),
                entry.getUserId(),
                entry.getBeerName(),
                entry.getVolumeMl(),
                entry.getAbv(),
                entry.getTimestamp()
        );
    }
}
