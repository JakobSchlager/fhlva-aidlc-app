package com.beertracker.auth.controller;

import com.beertracker.auth.dto.AuthResponse;
import com.beertracker.auth.dto.LoginRequest;
import com.beertracker.auth.dto.RegisterRequest;
import com.beertracker.auth.dto.UserResponse;
import com.beertracker.auth.service.AuthService;
import com.beertracker.auth.service.KeyService;
import jakarta.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseCookie;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CookieValue;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;

@RestController
@RequestMapping("/auth")
public class AuthController {

    private static final String REFRESH_TOKEN_COOKIE = "refreshToken";

    private final AuthService authService;
    private final KeyService keyService;

    public AuthController(AuthService authService, KeyService keyService) {
        this.authService = authService;
        this.keyService = keyService;
    }

    @PostMapping("/register")
    public ResponseEntity<UserResponse> register(@Valid @RequestBody RegisterRequest request) {
        UserResponse user = authService.register(request);
        return ResponseEntity.status(HttpStatus.CREATED).body(user);
    }

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        AuthService.LoginResult result = authService.login(request);

        ResponseCookie cookie = buildRefreshCookie(result.refreshToken(), Duration.ofDays(7));

        return ResponseEntity.ok()
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .body(new AuthResponse(result.accessToken()));
    }

    @PostMapping("/refresh")
    public ResponseEntity<AuthResponse> refresh(
            @CookieValue(name = REFRESH_TOKEN_COOKIE, required = false) String rawRefreshToken) {

        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        AuthService.LoginResult result = authService.refresh(rawRefreshToken);

        ResponseCookie cookie = buildRefreshCookie(result.refreshToken(), Duration.ofDays(7));

        return ResponseEntity.ok()
                .header(HttpHeaders.SET_COOKIE, cookie.toString())
                .body(new AuthResponse(result.accessToken()));
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(
            @CookieValue(name = REFRESH_TOKEN_COOKIE, required = false) String rawRefreshToken) {

        authService.logout(rawRefreshToken);

        ResponseCookie clearCookie = ResponseCookie.from(REFRESH_TOKEN_COOKIE, "")
                .httpOnly(true)
                .secure(true)
                .path("/auth")
                .maxAge(0)
                .sameSite("Strict")
                .build();

        return ResponseEntity.status(HttpStatus.NO_CONTENT)
                .header(HttpHeaders.SET_COOKIE, clearCookie.toString())
                .build();
    }

    @GetMapping("/.well-known/jwks.json")
    public ResponseEntity<String> jwks() {
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .body(keyService.getJwksJson());
    }

    private ResponseCookie buildRefreshCookie(String value, Duration maxAge) {
        return ResponseCookie.from(REFRESH_TOKEN_COOKIE, value)
                .httpOnly(true)
                .secure(true)
                .path("/auth")
                .maxAge(maxAge)
                .sameSite("Strict")
                .build();
    }
}
