package com.beertracker.tracking.controller;

import com.beertracker.tracking.dto.CreateEntryRequest;
import com.beertracker.tracking.dto.EntryResponse;
import com.beertracker.tracking.dto.PagedResponse;
import com.beertracker.tracking.service.EntryService;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.UUID;

@RestController
@RequestMapping("/tracking/entries")
public class EntryController {

    private final EntryService entryService;

    public EntryController(EntryService entryService) {
        this.entryService = entryService;
    }

    @PostMapping
    public ResponseEntity<EntryResponse> createEntry(
            @RequestBody @Valid CreateEntryRequest request,
            @AuthenticationPrincipal Jwt jwt) {
        UUID userId = UUID.fromString(jwt.getSubject());
        EntryResponse response = entryService.create(userId, request);
        return ResponseEntity.status(HttpStatus.CREATED).body(response);
    }

    @GetMapping
    public ResponseEntity<PagedResponse<EntryResponse>> listEntries(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
            @AuthenticationPrincipal Jwt jwt) {
        UUID userId = UUID.fromString(jwt.getSubject());
        Instant fromInstant = from != null ? from.atStartOfDay(ZoneOffset.UTC).toInstant() : null;
        Instant toInstant = to != null ? to.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant() : null;
        return ResponseEntity.ok(entryService.list(userId, page, size, fromInstant, toInstant));
    }

    @PutMapping("/{id}")
    public ResponseEntity<EntryResponse> updateEntry(
            @PathVariable UUID id,
            @RequestBody @Valid CreateEntryRequest request,
            @AuthenticationPrincipal Jwt jwt) {
        UUID userId = UUID.fromString(jwt.getSubject());
        return ResponseEntity.ok(entryService.update(userId, id, request));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deleteEntry(
            @PathVariable UUID id,
            @AuthenticationPrincipal Jwt jwt) {
        UUID userId = UUID.fromString(jwt.getSubject());
        entryService.delete(userId, id);
        return ResponseEntity.noContent().build();
    }
}
