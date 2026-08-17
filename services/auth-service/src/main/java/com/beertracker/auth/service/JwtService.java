package com.beertracker.auth.service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Date;
import java.util.UUID;

/**
 * Generates and validates RS256 JWTs using the RSA key pair from KeyService.
 */
@Service
public class JwtService {

    private final KeyService keyService;

    @Value("${app.auth.jwtExpirationMs}")
    private long jwtExpirationMs;

    public JwtService(KeyService keyService) {
        this.keyService = keyService;
    }

    public String generateToken(UUID userId, String email) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + jwtExpirationMs);

        return Jwts.builder()
                .subject(userId.toString())
                .claim("email", email)
                .issuedAt(now)
                .expiration(expiry)
                .signWith(keyService.getPrivateKey(), Jwts.SIG.RS256)
                .compact();
    }

    public Claims validateAndExtractClaims(String token) {
        return Jwts.parser()
                .verifyWith(keyService.getPublicKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }

    public UUID extractUserId(String token) {
        Claims claims = validateAndExtractClaims(token);
        return UUID.fromString(claims.getSubject());
    }

    public boolean isTokenValid(String token) {
        try {
            Claims claims = validateAndExtractClaims(token);
            return !claims.getExpiration().before(new Date());
        } catch (Exception e) {
            return false;
        }
    }
}
