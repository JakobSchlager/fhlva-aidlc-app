import React, { createContext, useState, useEffect, useCallback, useRef } from 'react'
import axios from 'axios'

interface AuthContextValue {
  accessToken: string | null
  isAuthenticated: boolean
  isInitialized: boolean
  login: (email: string, password: string) => Promise<void>
  register: (email: string, password: string) => Promise<void>
  logout: () => Promise<void>
}

export const AuthContext = createContext<AuthContextValue | null>(null)

interface JwtPayload {
  exp: number
  sub: string
}

function decodeJwt(token: string): JwtPayload | null {
  try {
    const payload = token.split('.')[1]
    const decoded = JSON.parse(atob(payload))
    return decoded as JwtPayload
  } catch {
    return null
  }
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [accessToken, setAccessToken] = useState<string | null>(null)
  const [isInitialized, setIsInitialized] = useState(false)
  const refreshTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const scheduleRefresh = useCallback((token: string) => {
    const payload = decodeJwt(token)
    if (!payload) return

    const expiresInMs = payload.exp * 1000 - Date.now()
    const refreshInMs = expiresInMs - 60_000 // 60s before expiry

    if (refreshTimerRef.current) {
      clearTimeout(refreshTimerRef.current)
    }

    if (refreshInMs <= 0) return

    refreshTimerRef.current = setTimeout(async () => {
      try {
        const response = await axios.post<{ accessToken: string }>('/auth/refresh', {}, { withCredentials: true })
        const newToken = response.data.accessToken
        setAccessToken(newToken)
        scheduleRefresh(newToken)
      } catch {
        setAccessToken(null)
      }
    }, refreshInMs)
  }, [])

  useEffect(() => {
    // On mount, attempt to restore session via refresh token cookie
    axios
      .post<{ accessToken: string }>('/auth/refresh', {}, { withCredentials: true })
      .then((response) => {
        const token = response.data.accessToken
        setAccessToken(token)
        scheduleRefresh(token)
      })
      .catch(() => {
        // No valid session — stay logged out
      })
      .finally(() => {
        setIsInitialized(true)
      })

    return () => {
      if (refreshTimerRef.current) {
        clearTimeout(refreshTimerRef.current)
      }
    }
  }, [scheduleRefresh])

  const login = useCallback(
    async (email: string, password: string) => {
      const response = await axios.post<{ accessToken: string }>(
        '/auth/login',
        { email, password },
        { withCredentials: true },
      )
      const token = response.data.accessToken
      setAccessToken(token)
      scheduleRefresh(token)
    },
    [scheduleRefresh],
  )

  const register = useCallback(async (email: string, password: string) => {
    await axios.post('/auth/register', { email, password })
  }, [])

  const logout = useCallback(async () => {
    try {
      await axios.post('/auth/logout', {}, { withCredentials: true })
    } finally {
      setAccessToken(null)
      if (refreshTimerRef.current) {
        clearTimeout(refreshTimerRef.current)
      }
    }
  }, [])

  return (
    <AuthContext.Provider
      value={{
        accessToken,
        isAuthenticated: accessToken !== null,
        isInitialized,
        login,
        register,
        logout,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}
