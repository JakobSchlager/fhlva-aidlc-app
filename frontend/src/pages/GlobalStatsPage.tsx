import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { getGlobalStats, type GlobalStats } from '@/services/api'

export default function GlobalStatsPage() {
  const [stats, setStats] = useState<GlobalStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const load = async () => {
      setLoading(true)
      setError(null)
      try {
        const res = await getGlobalStats()
        setStats(res.data)
      } catch {
        setError('Failed to load global statistics.')
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center gap-4">
          <Link to="/dashboard" className="text-sm text-amber-700 font-medium hover:text-amber-900">
            ← Dashboard
          </Link>
          <span className="text-lg font-semibold text-gray-800">Global Statistics</span>
        </div>
      </nav>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
        {loading && <p className="text-sm text-gray-500">Loading…</p>}
        {error && (
          <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {stats && (
          <>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
              <div className="bg-white rounded-lg shadow p-6">
                <p className="text-xs text-gray-500 uppercase tracking-wide">Active Users</p>
                <p className="mt-1 text-3xl font-bold text-amber-700">{stats.activeUsers}</p>
              </div>
              <div className="bg-white rounded-lg shadow p-6">
                <p className="text-xs text-gray-500 uppercase tracking-wide">
                  Global Avg Drinks / Day
                </p>
                <p className="mt-1 text-3xl font-bold text-amber-700">
                  {stats.globalAvgDrinksPerDay.toFixed(2)}
                </p>
              </div>
            </div>

            <div className="bg-white rounded-lg shadow p-6">
              <h2 className="text-base font-semibold text-gray-700 mb-3">Top Beers</h2>
              {stats.topBeerNames.length > 0 ? (
                <ol className="space-y-2">
                  {stats.topBeerNames.map((name, i) => (
                    <li key={name} className="flex items-center gap-3">
                      <span className="text-sm font-bold text-amber-600 w-6">{i + 1}.</span>
                      <span className="text-sm text-gray-800">{name}</span>
                    </li>
                  ))}
                </ol>
              ) : (
                <p className="text-sm text-gray-400">No data available yet</p>
              )}
            </div>

            <p className="text-xs text-gray-400">
              Cached at {new Date(stats.cachedAt).toLocaleString()}
            </p>
          </>
        )}
      </main>
    </div>
  )
}
