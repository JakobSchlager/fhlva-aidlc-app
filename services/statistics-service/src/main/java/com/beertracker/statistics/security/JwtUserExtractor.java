package com.beertracker.statistics.security;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;

import java.util.UUID;

/**
 * Utility component that extracts the authenticated user's ID from a validated JWT.
 * The JWT {@code sub} claim carries the user's UUID as set by the auth-service.
 */
@Component
public class JwtUserExtractor {

    /**
     * Returns the user ID (UUID) from the JWT {@code sub} claim.
     *
     * @param jwt validated JWT principal
     * @return the user's UUID
     * @throws IllegalArgumentException if the {@code sub} claim is absent or not a valid UUID
     */
    public UUID extractUserId(Jwt jwt) {
        String subject = jwt.getSubject();
        if (subject == null || subject.isBlank()) {
            throw new IllegalArgumentException("JWT sub claim is missing");
        }
        try {
            return UUID.fromString(subject);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("JWT sub claim is not a valid UUID: " + subject, e);
        }
    }
}
