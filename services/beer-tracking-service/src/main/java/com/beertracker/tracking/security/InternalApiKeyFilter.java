package com.beertracker.tracking.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class InternalApiKeyFilter extends OncePerRequestFilter {

    private static final String INTERNAL_PATH_PREFIX = "/internal/";
    private static final String API_KEY_HEADER = "X-Internal-Key";

    private final String apiKey;

    public InternalApiKeyFilter(@Value("${app.internal.apiKey}") String apiKey) {
        this.apiKey = apiKey;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        if (request.getServletPath().startsWith(INTERNAL_PATH_PREFIX)) {
            String providedKey = request.getHeader(API_KEY_HEADER);
            if (providedKey == null || !providedKey.equals(apiKey)) {
                response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                response.setContentType("application/json");
                response.getWriter().write("{\"error\":\"Unauthorized: missing or invalid X-Internal-Key\"}");
                return;
            }
        }
        filterChain.doFilter(request, response);
    }
}
