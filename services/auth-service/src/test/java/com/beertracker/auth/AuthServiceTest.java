package com.beertracker.auth;

import com.beertracker.auth.dto.LoginRequest;
import com.beertracker.auth.dto.RegisterRequest;
import com.beertracker.auth.dto.UserResponse;
import com.beertracker.auth.entity.RefreshToken;
import com.beertracker.auth.entity.User;
import com.beertracker.auth.repository.RefreshTokenRepository;
import com.beertracker.auth.repository.UserRepository;
import com.beertracker.auth.service.AuthService;
import com.beertracker.auth.service.JwtService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private RefreshTokenRepository refreshTokenRepository;

    @Mock
    private JwtService jwtService;

    private BCryptPasswordEncoder passwordEncoder;
    private AuthService authService;

    @BeforeEach
    void setUp() {
        passwordEncoder = new BCryptPasswordEncoder();
        authService = new AuthService(userRepository, refreshTokenRepository, jwtService, passwordEncoder);
        ReflectionTestUtils.setField(authService, "refreshTokenExpiryDays", 7);
    }

    // -------------------------------------------------------------------------
    // Registration tests
    // -------------------------------------------------------------------------

    @Test
    void register_successfulRegistration_returnsUserResponse() {
        RegisterRequest request = new RegisterRequest("alice@example.com", "securePass1");

        when(userRepository.existsByEmail("alice@example.com")).thenReturn(false);

        UUID generatedId = UUID.randomUUID();
        when(userRepository.save(any(User.class))).thenAnswer(inv -> {
            User u = inv.getArgument(0);
            u.setId(generatedId);
            return u;
        });

        UserResponse response = authService.register(request);

        assertThat(response.getId()).isEqualTo(generatedId);
        assertThat(response.getEmail()).isEqualTo("alice@example.com");

        ArgumentCaptor<User> userCaptor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(userCaptor.capture());
        User savedUser = userCaptor.getValue();
        assertThat(passwordEncoder.matches("securePass1", savedUser.getPasswordHash())).isTrue();
    }

    @Test
    void register_duplicateEmail_throwsConflict() {
        RegisterRequest request = new RegisterRequest("bob@example.com", "password123");

        when(userRepository.existsByEmail("bob@example.com")).thenReturn(true);

        assertThatThrownBy(() -> authService.register(request))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> {
                    ResponseStatusException rse = (ResponseStatusException) ex;
                    assertThat(rse.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);
                });
    }

    @Test
    void register_emailNormalized_lowercaseAndTrimmed() {
        RegisterRequest request = new RegisterRequest("  CHARLIE@Example.COM  ", "password123");

        when(userRepository.existsByEmail("charlie@example.com")).thenReturn(false);

        UUID generatedId = UUID.randomUUID();
        when(userRepository.save(any(User.class))).thenAnswer(inv -> {
            User u = inv.getArgument(0);
            u.setId(generatedId);
            return u;
        });

        UserResponse response = authService.register(request);

        assertThat(response.getEmail()).isEqualTo("charlie@example.com");
    }

    // -------------------------------------------------------------------------
    // Login tests
    // -------------------------------------------------------------------------

    @Test
    void login_validCredentials_returnsLoginResult() {
        String rawPassword = "correctPass1";
        String hashed = passwordEncoder.encode(rawPassword);

        User user = new User("dave@example.com", hashed);
        user.setId(UUID.randomUUID());

        when(userRepository.findByEmail("dave@example.com")).thenReturn(Optional.of(user));
        when(jwtService.generateToken(user.getId(), user.getEmail())).thenReturn("mocked.jwt.token");
        when(refreshTokenRepository.save(any(RefreshToken.class))).thenAnswer(inv -> inv.getArgument(0));

        LoginRequest loginRequest = new LoginRequest("dave@example.com", rawPassword);
        AuthService.LoginResult result = authService.login(loginRequest);

        assertThat(result.accessToken()).isEqualTo("mocked.jwt.token");
        assertThat(result.refreshToken()).isNotBlank();
    }

    @Test
    void login_invalidPassword_throwsUnauthorized() {
        String hashed = passwordEncoder.encode("correctPass1");

        User user = new User("eve@example.com", hashed);
        user.setId(UUID.randomUUID());

        when(userRepository.findByEmail("eve@example.com")).thenReturn(Optional.of(user));

        LoginRequest loginRequest = new LoginRequest("eve@example.com", "wrongPassword");

        assertThatThrownBy(() -> authService.login(loginRequest))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> {
                    ResponseStatusException rse = (ResponseStatusException) ex;
                    assertThat(rse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
                });
    }

    @Test
    void login_unknownEmail_throwsUnauthorized() {
        when(userRepository.findByEmail(anyString())).thenReturn(Optional.empty());

        LoginRequest loginRequest = new LoginRequest("nobody@example.com", "password123");

        assertThatThrownBy(() -> authService.login(loginRequest))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> {
                    ResponseStatusException rse = (ResponseStatusException) ex;
                    assertThat(rse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
                });
    }

    // -------------------------------------------------------------------------
    // Refresh token rotation tests
    // -------------------------------------------------------------------------

    @Test
    void refresh_validToken_rotatesAndReturnsNewTokens() {
        UUID userId = UUID.randomUUID();
        User user = new User("frank@example.com", "hash");
        user.setId(userId);

        // We need to capture what token hash gets stored from the "login" step,
        // so we simulate using a known raw token instead.
        String rawToken = "known-raw-token-value-for-test-purposes-1234567890abcdefgh";

        // Compute the hash the same way AuthService does
        String tokenHash = computeSha256Base64Url(rawToken);

        RefreshToken storedToken = new RefreshToken(userId, tokenHash,
                OffsetDateTime.now().plusDays(7));
        storedToken.setId(UUID.randomUUID());

        when(refreshTokenRepository.findByTokenHash(tokenHash)).thenReturn(Optional.of(storedToken));
        when(userRepository.findById(userId)).thenReturn(Optional.of(user));
        when(jwtService.generateToken(userId, user.getEmail())).thenReturn("new.access.token");
        when(refreshTokenRepository.save(any(RefreshToken.class))).thenAnswer(inv -> inv.getArgument(0));

        AuthService.LoginResult result = authService.refresh(rawToken);

        assertThat(result.accessToken()).isEqualTo("new.access.token");
        assertThat(result.refreshToken()).isNotBlank();
        assertThat(storedToken.isRevoked()).isTrue();
    }

    @Test
    void refresh_expiredToken_throwsUnauthorized() {
        UUID userId = UUID.randomUUID();
        String rawToken = "expired-token-value-1234567890abcdefghijklmnopqrstuvwx";
        String tokenHash = computeSha256Base64Url(rawToken);

        RefreshToken expiredToken = new RefreshToken(userId, tokenHash,
                OffsetDateTime.now().minusDays(1));
        expiredToken.setId(UUID.randomUUID());

        when(refreshTokenRepository.findByTokenHash(tokenHash)).thenReturn(Optional.of(expiredToken));

        assertThatThrownBy(() -> authService.refresh(rawToken))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> {
                    ResponseStatusException rse = (ResponseStatusException) ex;
                    assertThat(rse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
                });
    }

    @Test
    void refresh_revokedToken_throwsUnauthorized() {
        UUID userId = UUID.randomUUID();
        String rawToken = "revoked-token-value-1234567890abcdefghijklmnopqrstuvwx";
        String tokenHash = computeSha256Base64Url(rawToken);

        RefreshToken revokedToken = new RefreshToken(userId, tokenHash,
                OffsetDateTime.now().plusDays(7));
        revokedToken.setId(UUID.randomUUID());
        revokedToken.setRevoked(true);

        when(refreshTokenRepository.findByTokenHash(tokenHash)).thenReturn(Optional.of(revokedToken));

        assertThatThrownBy(() -> authService.refresh(rawToken))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(ex -> {
                    ResponseStatusException rse = (ResponseStatusException) ex;
                    assertThat(rse.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
                });
    }

    // -------------------------------------------------------------------------
    // Helper — mirrors AuthService.hashToken()
    // -------------------------------------------------------------------------

    private String computeSha256Base64Url(String raw) {
        try {
            java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(raw.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            return java.util.Base64.getUrlEncoder().withoutPadding().encodeToString(hash);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
