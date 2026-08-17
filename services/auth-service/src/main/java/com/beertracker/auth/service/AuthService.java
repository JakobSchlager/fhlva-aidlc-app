package com.beertracker.auth.service;

import com.beertracker.auth.dto.AuthResponse;
import com.beertracker.auth.dto.LoginRequest;
import com.beertracker.auth.dto.RegisterRequest;
import com.beertracker.auth.dto.UserResponse;
import com.beertracker.auth.entity.RefreshToken;
import com.beertracker.auth.entity.User;
import com.beertracker.auth.repository.RefreshTokenRepository;
import com.beertracker.auth.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.Base64;
import java.util.UUID;

@Service
public class AuthService {

    private static final Logger log = LoggerFactory.getLogger(AuthService.class);

    private final UserRepository userRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final JwtService jwtService;
    private final BCryptPasswordEncoder passwordEncoder;
    private final SecureRandom secureRandom = new SecureRandom();

    @Value("${app.auth.refreshTokenExpiryDays}")
    private int refreshTokenExpiryDays;

    public AuthService(UserRepository userRepository,
                       RefreshTokenRepository refreshTokenRepository,
                       JwtService jwtService,
                       BCryptPasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.jwtService = jwtService;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional
    public UserResponse register(RegisterRequest request) {
        String email = request.getEmail().toLowerCase().trim();

        if (userRepository.existsByEmail(email)) {
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "An account with this email already exists");
        }

        String hash = passwordEncoder.encode(request.getPassword());
        User user = new User(email, hash);
        user = userRepository.save(user);

        log.info("Registered new user id={}", user.getId());
        return new UserResponse(user.getId(), user.getEmail());
    }

    @Transactional
    public LoginResult login(LoginRequest request) {
        String email = request.getEmail().toLowerCase().trim();

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                        "Invalid credentials"));

        if (!passwordEncoder.matches(request.getPassword(), user.getPasswordHash())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid credentials");
        }

        String accessToken = jwtService.generateToken(user.getId(), user.getEmail());
        String rawRefreshToken = generateRawRefreshToken();
        String tokenHash = hashToken(rawRefreshToken);

        OffsetDateTime expiresAt = OffsetDateTime.now().plusDays(refreshTokenExpiryDays);
        RefreshToken refreshToken = new RefreshToken(user.getId(), tokenHash, expiresAt);
        refreshTokenRepository.save(refreshToken);

        log.info("User logged in id={}", user.getId());
        return new LoginResult(accessToken, rawRefreshToken);
    }

    @Transactional
    public LoginResult refresh(String rawRefreshToken) {
        String tokenHash = hashToken(rawRefreshToken);

        RefreshToken stored = refreshTokenRepository.findByTokenHash(tokenHash)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                        "Invalid refresh token"));

        if (stored.isRevoked()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Refresh token has been revoked");
        }

        if (stored.getExpiresAt().isBefore(OffsetDateTime.now())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Refresh token has expired");
        }

        User user = userRepository.findById(stored.getUserId())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED,
                        "User not found"));

        // Rotate: revoke old token, issue new one
        stored.setRevoked(true);
        refreshTokenRepository.save(stored);

        String accessToken = jwtService.generateToken(user.getId(), user.getEmail());
        String newRawToken = generateRawRefreshToken();
        String newTokenHash = hashToken(newRawToken);

        OffsetDateTime expiresAt = OffsetDateTime.now().plusDays(refreshTokenExpiryDays);
        RefreshToken newRefreshToken = new RefreshToken(user.getId(), newTokenHash, expiresAt);
        refreshTokenRepository.save(newRefreshToken);

        log.info("Refresh token rotated for userId={}", user.getId());
        return new LoginResult(accessToken, newRawToken);
    }

    @Transactional
    public void logout(String rawRefreshToken) {
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            return;
        }
        String tokenHash = hashToken(rawRefreshToken);
        refreshTokenRepository.findByTokenHash(tokenHash).ifPresent(rt -> {
            rt.setRevoked(true);
            refreshTokenRepository.save(rt);
            log.info("Refresh token revoked for userId={}", rt.getUserId());
        });
    }

    private String generateRawRefreshToken() {
        byte[] bytes = new byte[64];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String hashToken(String rawToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            return Base64.getUrlEncoder().withoutPadding().encodeToString(hash);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to hash token", e);
        }
    }

    public record LoginResult(String accessToken, String refreshToken) {
    }
}
