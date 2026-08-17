package com.beertracker.tracking.dto;

import java.util.List;

public record PagedResponse<T>(
        List<T> items,
        int page,
        int pageSize,
        long totalCount
) {
}
