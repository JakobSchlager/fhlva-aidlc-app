import { useEffect } from 'react'
import { Routes, Route, Navigate } from 'react-router-dom'
import { AuthProvider } from '@/contexts/AuthContext'
import { useAuth } from '@/hooks/useAuth'
import { setTokenAccessor } from '@/services/api'
import ProtectedRoute from '@/components/auth/ProtectedRoute'
import LoginPage from '@/pages/LoginPage'
import RegisterPage from '@/pages/RegisterPage'
import DashboardPage from '@/pages/DashboardPage'
import HistoryPage from '@/pages/HistoryPage'
import StatsPage from '@/pages/StatsPage'
import GlobalStatsPage from '@/pages/GlobalStatsPage'
import NotFoundPage from '@/pages/NotFoundPage'

function RootRedirect() {
  const { isAuthenticated } = useAuth()
  return <Navigate to={isAuthenticated ? '/dashboard' : '/login'} replace />
}

function TokenBridge() {
  const { accessToken } = useAuth()
  useEffect(() => {
    setTokenAccessor(() => accessToken)
  }, [accessToken])
  return null
}

export default function App() {
  return (
    <AuthProvider>
      <TokenBridge />
      <Routes>
        <Route path="/" element={<RootRedirect />} />
        <Route path="/login" element={<LoginPage />} />
        <Route path="/register" element={<RegisterPage />} />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute>
              <DashboardPage />
            </ProtectedRoute>
          }
        />
        <Route
          path="/history"
          element={
            <ProtectedRoute>
              <HistoryPage />
            </ProtectedRoute>
          }
        />
        <Route
          path="/stats"
          element={
            <ProtectedRoute>
              <StatsPage />
            </ProtectedRoute>
          }
        />
        <Route
          path="/global"
          element={
            <ProtectedRoute>
              <GlobalStatsPage />
            </ProtectedRoute>
          }
        />
        <Route path="*" element={<NotFoundPage />} />
      </Routes>
    </AuthProvider>
  )
}
