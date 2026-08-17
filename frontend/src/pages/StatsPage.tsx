import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
  CartesianGrid,
} from 'recharts'
import { getPersonalStats, getTrend, type PersonalStats } from '@/services/api'

export default function StatsPage() {
  const [stats, setStats] = useState<PersonalStats | null>(null)
  const [trend, setTrend] = useState<{ date: string; drinks: number }[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const load = async () => {
      setLoading(true)
      setError(null)
      try {
        const [statsRes, trendRes] = await Promise.all([
          getPersonalStats(),
          getTrend(30),
        ])
        setStats(statsRes.data)
        // TrendApiResponse has { data: TrendPoint[], cachedAt: string }
        setTrend(
          (trendRes.data.data ?? []).map((p) => ({
            date: new Date(p.date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
            drinks: Number(p.standardDrinks),
          }))
        )
      } catch {
        setError('Failed to load statistics.')
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  // byDayOfWeek is an array of { dayName, avgDrinks } from the backend
  const byDayData = stats
    ? (stats.byDayOfWeek ?? []).map((entry) => ({
        day: entry.dayName.slice(0, 3),
        drinks: Number(entry.avgDrinks),
      }))
    : []

  const trendData = trend

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center gap-4">
          <Link to="/dashboard" className="text-sm text-amber-700 font-medium hover:text-amber-900">
            ← Dashboard
          </Link>
          <span className="text-lg font-semibold text-gray-800">My Statistics</span>
        </div>
      </nav>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
        {loading && <p className="text-sm text-gray-500">Loading…</p>}
        {error && (
          <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">
            {error}
          </div>
        )}

        {stats && (
          <>
            {/* Stat tiles */}
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
              <StatTile label="Total Entries" value={stats.totalEntries} />
              <StatTile label="Total Volume (ml)" value={stats.totalVolumeMl} />
              <StatTile
                label="Standard Drinks"
                value={stats.totalStandardDrinks != null ? Number(stats.totalStandardDrinks).toFixed(1) : null}
              />
              <StatTile label="Avg / Day" value={stats.avgDrinksPerDay != null ? Number(stats.avgDrinksPerDay).toFixed(2) : null} />
            </div>

            {/* Bar chart by day of week */}
            <div className="bg-white rounded-lg shadow p-6">
              <h2 className="text-base font-semibold text-gray-700 mb-4">
                Standard Drinks by Day of Week
              </h2>
              <ResponsiveContainer width="100%" height={260}>
                <BarChart data={byDayData}>
                  <XAxis dataKey="day" tick={{ fontSize: 12 }} />
                  <YAxis tick={{ fontSize: 12 }} />
                  <Tooltip />
                  <Bar dataKey="drinks" fill="#d97706" radius={[4, 4, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>

            {/* Line chart trend */}
            {trendData.length > 0 && (
              <div className="bg-white rounded-lg shadow p-6">
                <h2 className="text-base font-semibold text-gray-700 mb-4">
                  Last 30 Days — Daily Standard Drinks
                </h2>
                <ResponsiveContainer width="100%" height={260}>
                  <LineChart data={trendData}>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                    <XAxis
                      dataKey="date"
                      tick={{ fontSize: 11 }}
                      interval={Math.floor(trendData.length / 7)}
                    />
                    <YAxis tick={{ fontSize: 12 }} />
                    <Tooltip />
                    <Line
                      type="monotone"
                      dataKey="drinks"
                      stroke="#d97706"
                      strokeWidth={2}
                      dot={false}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            )}

            <p className="text-xs text-gray-400">
              Cached at {new Date(stats.cachedAt).toLocaleString()}
            </p>
          </>
        )}
      </main>
    </div>
  )
}

function StatTile({ label, value }: { label: string; value: string | number | null | undefined }) {
  return (
    <div className="bg-white rounded-lg shadow p-4">
      <p className="text-xs text-gray-500 uppercase tracking-wide">{label}</p>
      <p className="mt-1 text-2xl font-bold text-amber-700">{value ?? '—'}</p>
    </div>
  )
}
