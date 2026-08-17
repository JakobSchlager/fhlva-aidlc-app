package com.beertracker.statistics.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
public class AppConfig {

    /**
     * Shared RestTemplate used by the tracking service client for internal API calls.
     */
    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
