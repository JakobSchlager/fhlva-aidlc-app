package com.beertracker.auth.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private static final Logger log = LoggerFactory.getLogger(SecurityConfig.class);

    /** BCrypt cost used so far (Spring's default). Each +1 doubles the time per hash. */
    private static final int DEFAULT_STRENGTH = 10;

    /**
     * Feature flag FEATURE_STRONG_PASSWORD_HASH (off by default): hash new passwords with a higher
     * BCrypt cost (PASSWORD_HASH_STRENGTH, default 14), as current password-storage guidance suggests.
     * Safer against offline cracking, but every register and every login of such a user costs
     * 2^(strength-10) times the CPU: at 14 that is 16 times. Existing hashes keep the cost they were
     * created with, because BCrypt stores it in the hash.
     */
    @Bean
    public BCryptPasswordEncoder passwordEncoder(
            @Value("${FEATURE_STRONG_PASSWORD_HASH:false}") boolean strongHash,
            @Value("${PASSWORD_HASH_STRENGTH:14}") int strongStrength) {
        int strength = strongHash ? strongStrength : DEFAULT_STRENGTH;
        log.info("Feature STRONG_PASSWORD_HASH {}: BCrypt strength {}", strongHash ? "ON" : "off", strength);
        return new BCryptPasswordEncoder(strength);
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(authz -> authz
                .requestMatchers(
                    "GET", "/auth/.well-known/jwks.json"
                ).permitAll()
                .requestMatchers(
                    "POST", "/auth/register"
                ).permitAll()
                .requestMatchers(
                    "POST", "/auth/login"
                ).permitAll()
                .requestMatchers(
                    "POST", "/auth/refresh"
                ).permitAll()
                .requestMatchers(
                    "POST", "/auth/logout"
                ).permitAll()
                .requestMatchers("/actuator/health/**").permitAll()
                .anyRequest().authenticated()
            );

        return http.build();
    }
}
