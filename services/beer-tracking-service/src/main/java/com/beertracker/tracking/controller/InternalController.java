package com.beertracker.tracking.controller;

import com.beertracker.tracking.dto.SummaryResponse;
import com.beertracker.tracking.service.EntryService;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/internal/tracking")
public class InternalController {

    private final EntryService entryService;

    public InternalController(EntryService entryService) {
        this.entryService = entryService;
    }

    @GetMapping("/users")
    public ResponseEntity<List<UUID>> listUsers() {
        return ResponseEntity.ok(entryService.listDistinctUserIds());
    }

    @GetMapping("/summary")
    public ResponseEntity<SummaryResponse> getSummary(
            @RequestParam UUID userId,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        Instant fromInstant = from.atStartOfDay(ZoneOffset.UTC).toInstant();
        Instant toInstant = to.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant();
        return ResponseEntity.ok(entryService.getSummary(userId, fromInstant, toInstant));
    }
}
