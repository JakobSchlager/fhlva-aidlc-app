import axios, { type InternalAxiosRequestConfig } from 'axios'

// Token accessor — set by AuthContext after mount
let getAccessToken: (() => string | null) | null = null

export function setTokenAccessor(fn: () => string | null) {
  getAccessToken = fn
}

const api = axios.create({
  baseURL: '',
  withCredentials: true,
})

api.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  const token = getAccessToken ? getAccessToken() : null
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      window.location.href = '/login'
    }
    return Promise.reject(error)
  },
)

// ─── Types ────────────────────────────────────────────────────────────────────

export interface TrackingEntry {
  id: string
  beerName: string
  volumeMl: number
  abv: number
  timestamp: string
  standardDrinks?: number
}

export interface TrackingEntryInput {
  beerName: string
  volumeMl: number
  abv: number
  timestamp?: string
}

export interface PaginatedEntries {
  items: TrackingEntry[]
  page: number
  pageSize: number
  totalCount: number
}

export interface Warning {
  id: string
  type: 'DAILY_EXCEEDED' | 'WEEKLY_EXCEEDED'
  triggeredAt: string
  status: 'ACTIVE' | 'ACKNOWLEDGED'
}

export interface PersonalStats {
  totalEntries: number | null
  totalVolumeMl: number
  totalStandardDrinks: number
  avgDrinksPerDay: number
  byDayOfWeek: DayOfWeekStat[]
  cachedAt: string
}

export interface TrendPoint {
  date: string
  standardDrinks: number
}

export interface TrendApiResponse {
  data: TrendPoint[]
  cachedAt: string
}

export interface DayOfWeekStat {
  dayName: string
  avgDrinks: number
}

export interface GlobalStats {
  activeUsers: number
  globalAvgDrinksPerDay: number
  topBeerNames: string[]
  cachedAt: string
}

// ─── Auth ─────────────────────────────────────────────────────────────────────

export const loginApi = (email: string, password: string) =>
  api.post<{ accessToken: string }>('/auth/login', { email, password })

export const registerApi = (email: string, password: string) =>
  api.post('/auth/register', { email, password })

export const logoutApi = () => api.post('/auth/logout')

export const refreshApi = () => api.post<{ accessToken: string }>('/auth/refresh')

// ─── Tracking ─────────────────────────────────────────────────────────────────

export const getEntries = (page = 0, size = 20, from?: string, to?: string) =>
  api.get<PaginatedEntries>('/tracking/entries', {
    params: { page, size, from, to },
  })

export const createEntry = (data: TrackingEntryInput) =>
  api.post<TrackingEntry>('/tracking/entries', data)

export const updateEntry = (id: string, data: TrackingEntryInput) =>
  api.put<TrackingEntry>(`/tracking/entries/${id}`, data)

export const deleteEntry = (id: string) => api.delete(`/tracking/entries/${id}`)

// ─── Notifications ────────────────────────────────────────────────────────────

export interface PaginatedWarnings {
  content: Warning[]
  page: number
  size: number
  totalElements: number
  totalPages: number
  last: boolean
}

export const getWarnings = (status?: string) =>
  api.get<PaginatedWarnings>('/notifications/warnings', { params: status ? { status } : undefined })

export const acknowledgeWarning = (id: string) =>
  api.post(`/notifications/warnings/${id}/acknowledge`)

// ─── Statistics ───────────────────────────────────────────────────────────────

export const getPersonalStats = (from?: string, to?: string) =>
  api.get<PersonalStats>('/statistics/me', { params: { from, to } })

export const getTrend = (days?: number) =>
  api.get<TrendApiResponse>('/statistics/me/trend', { params: days ? { days } : undefined })

export const getGlobalStats = () => api.get<GlobalStats>('/statistics/global')

export default api
