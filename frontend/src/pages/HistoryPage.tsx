import { useState, useEffect, useCallback } from 'react'
import { Link } from 'react-router-dom'
import { getEntries, type TrackingEntry } from '@/services/api'
import EntryTable from '@/components/beer/EntryTable'

const PAGE_SIZE = 20

export default function HistoryPage() {
  const [entries, setEntries] = useState<TrackingEntry[]>([])
  const [page, setPage] = useState(0)
  const [totalPages, setTotalPages] = useState(0)
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [refreshKey, setRefreshKey] = useState(0)

  const fetchEntries = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await getEntries(
        page,
        PAGE_SIZE,
        from ? new Date(from).toISOString() : undefined,
        to ? new Date(to).toISOString() : undefined,
      )
      setEntries(res.data.items)
      setTotalPages(Math.ceil(res.data.totalCount / PAGE_SIZE))
    } catch {
      setError('Failed to load entries.')
    } finally {
      setLoading(false)
    }
  }, [page, from, to, refreshKey]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    fetchEntries()
  }, [fetchEntries])

  const handleFilterApply = () => {
    setPage(0)
    setRefreshKey((k) => k + 1)
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white border-b border-gray-200">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 h-14 flex items-center gap-4">
          <Link to="/dashboard" className="text-sm text-amber-700 font-medium hover:text-amber-900">
            ← Dashboard
          </Link>
          <span className="text-lg font-semibold text-gray-800">History</span>
        </div>
      </nav>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
        {/* Filters */}
        <div className="bg-white rounded-lg shadow p-4 flex flex-wrap items-end gap-4">
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">From</label>
            <input
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
              className="rounded-md border-gray-300 text-sm focus:border-amber-500 focus:ring-amber-500"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-gray-600 mb-1">To</label>
            <input
              type="date"
              value={to}
              onChange={(e) => setTo(e.target.value)}
              className="rounded-md border-gray-300 text-sm focus:border-amber-500 focus:ring-amber-500"
            />
          </div>
          <button
            onClick={handleFilterApply}
            className="px-4 py-2 bg-amber-600 text-white text-sm rounded-md hover:bg-amber-700"
          >
            Apply
          </button>
          {(from || to) && (
            <button
              onClick={() => {
                setFrom('')
                setTo('')
                setPage(0)
                setRefreshKey((k) => k + 1)
              }}
              className="px-4 py-2 border border-gray-300 text-sm rounded-md hover:bg-gray-50"
            >
              Clear
            </button>
          )}
        </div>

        {/* Table */}
        {error && (
          <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">
            {error}
          </div>
        )}
        <EntryTable
          entries={entries}
          loading={loading}
          page={page}
          totalPages={totalPages}
          onPrev={() => setPage((p) => Math.max(0, p - 1))}
          onNext={() => setPage((p) => p + 1)}
          onRefresh={() => setRefreshKey((k) => k + 1)}
        />
      </main>
    </div>
  )
}
