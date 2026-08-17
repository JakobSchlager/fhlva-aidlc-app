import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '@/hooks/useAuth'
import { getPersonalStats, type PersonalStats } from '@/services/api'
import BeerEntryForm from '@/components/beer/BeerEntryForm'
import NotificationsPanel from '@/components/notifications/NotificationsPanel'

export default function DashboardPage() {
  const { logout } = useAuth()
  const [stats, setStats] = useState<PersonalStats | null>(null)
  const [statsError, setStatsError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const fetchStats = useCallback(async () => {
    try {
      const res = await getPersonalStats()
      setStats(res.data)
      setStatsError(null)
    } catch {
      setStatsError('Failed to load statistics.')
    }
  }, [])

  useEffect(() => {
    fetchStats()
  }, [fetchStats, refreshKey])

  const handleEntryCreated = () => {
    setRefreshKey((k) => k + 1)
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center justify-between">
          <span className="text-lg font-semibold text-amber-700">Beer Tracker</span>
          <div className="flex items-center gap-4">
            <Link to="/history" className="text-sm text-gray-600 hover:text-gray-900">
              History
            </Link>
            <Link to="/stats" className="text-sm text-gray-600 hover:text-gray-900">
              My Stats
            </Link>
            <Link to="/global" className="text-sm text-gray-600 hover:text-gray-900">
              Global
            </Link>
            <button
              onClick={logout}
              className="text-sm text-gray-500 hover:text-gray-800"
            >
              Sign out
            </button>
          </div>
        </div>
      </nav>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        <h1 className="text-2xl font-bold text-gray-900">Dashboard</h1>

        {/* Notifications */}
        <NotificationsPanel />

        {/* Quick stats */}
        <section>
          <h2 className="text-lg font-semibold text-gray-700 mb-3">Your Stats</h2>
          {statsError && (
            <p className="text-sm text-red-600">{statsError}</p>
          )}
          {!stats && !statsError && (
            <p className="text-sm text-gray-500">Loading…</p>
          )}
          {stats && (
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <StatTile label="Total Entries" value={stats.totalEntries} />
              <StatTile label="Total Volume (ml)" value={stats.totalVolumeMl} />
              <StatTile
                label="Standard Drinks"
                value={stats.totalStandardDrinks != null ? Number(stats.totalStandardDrinks).toFixed(1) : null}
              />
              <StatTile
                label="Avg / Day"
                value={stats.avgDrinksPerDay != null ? Number(stats.avgDrinksPerDay).toFixed(2) : null}
              />
            </div>
          )}
        </section>

        {/* Log entry */}
        <section className="bg-white rounded-lg shadow p-6">
          <h2 className="text-lg font-semibold text-gray-700 mb-4">Log a Beer</h2>
          <BeerEntryForm onEntryCreated={handleEntryCreated} />
        </section>
      </main>
    </div>
  )
}

function StatTile({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <div className="bg-white rounded-lg shadow p-4" data-testid="stat-tile">
      <p className="text-xs text-gray-500 uppercase tracking-wide">{label}</p>
      <p className="mt-1 text-2xl font-bold text-amber-700">{value ?? '—'}</p>
    </div>
  )
}
