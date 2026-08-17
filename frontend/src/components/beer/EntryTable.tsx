import { useState } from 'react'
import { updateEntry, deleteEntry, type TrackingEntry, type TrackingEntryInput } from '@/services/api'

interface EntryTableProps {
  entries: TrackingEntry[]
  loading?: boolean
  page: number
  totalPages: number
  onPrev: () => void
  onNext: () => void
  onRefresh: () => void
}

export default function EntryTable({
  entries,
  loading = false,
  page,
  totalPages,
  onPrev,
  onNext,
  onRefresh,
}: EntryTableProps) {
  const [editingId, setEditingId] = useState<string | null>(null)
  const [editData, setEditData] = useState<Partial<TrackingEntryInput>>({})
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  const startEdit = (entry: TrackingEntry) => {
    setEditingId(entry.id)
    setEditData({
      beerName: entry.beerName,
      volumeMl: entry.volumeMl,
      abv: entry.abv,
      timestamp: entry.timestamp ? entry.timestamp.slice(0, 16) : '',
    })
    setActionError(null)
  }

  const cancelEdit = () => {
    setEditingId(null)
    setEditData({})
  }

  const saveEdit = async (id: string) => {
    if (!editData.beerName || editData.volumeMl === undefined || editData.abv === undefined) return
    try {
      const payload: TrackingEntryInput = {
        beerName: editData.beerName,
        volumeMl: Number(editData.volumeMl),
        abv: Number(editData.abv),
      }
      if (editData.timestamp) {
        payload.timestamp = new Date(editData.timestamp).toISOString()
      }
      await updateEntry(id, payload)
      setEditingId(null)
      onRefresh()
    } catch {
      setActionError('Failed to save changes.')
    }
  }

  const confirmDelete = async (id: string) => {
    try {
      await deleteEntry(id)
      setDeletingId(null)
      onRefresh()
    } catch {
      setActionError('Failed to delete entry.')
    }
  }

  return (
    <div>
      {actionError && (
        <div className="mb-3 rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">
          {actionError}
        </div>
      )}
      <div className="overflow-x-auto rounded-lg border border-gray-200">
        <table className="min-w-full divide-y divide-gray-200 text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left font-medium text-gray-500">Date</th>
              <th className="px-4 py-3 text-left font-medium text-gray-500">Beer</th>
              <th className="px-4 py-3 text-right font-medium text-gray-500">Volume (ml)</th>
              <th className="px-4 py-3 text-right font-medium text-gray-500">ABV (%)</th>
              <th className="px-4 py-3 text-right font-medium text-gray-500">Std Drinks</th>
              <th className="px-4 py-3 text-right font-medium text-gray-500">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100 bg-white">
            {loading && (
              <tr>
                <td colSpan={6} className="px-4 py-6 text-center text-gray-400">
                  Loading…
                </td>
              </tr>
            )}
            {!loading && entries.map((entry) =>
              editingId === entry.id ? (
                <tr key={entry.id} className="bg-amber-50">
                  <td className="px-4 py-2">
                    <input
                      type="datetime-local"
                      value={editData.timestamp ?? ''}
                      onChange={(e) => setEditData((d) => ({ ...d, timestamp: e.target.value }))}
                      className="w-full text-xs rounded border-gray-300 focus:border-amber-500 focus:ring-amber-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="text"
                      value={editData.beerName ?? ''}
                      onChange={(e) => setEditData((d) => ({ ...d, beerName: e.target.value }))}
                      className="w-full text-xs rounded border-gray-300 focus:border-amber-500 focus:ring-amber-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="number"
                      value={editData.volumeMl ?? ''}
                      onChange={(e) =>
                        setEditData((d) => ({ ...d, volumeMl: Number(e.target.value) }))
                      }
                      className="w-full text-xs rounded border-gray-300 focus:border-amber-500 focus:ring-amber-500"
                    />
                  </td>
                  <td className="px-4 py-2">
                    <input
                      type="number"
                      step="0.1"
                      value={editData.abv ?? ''}
                      onChange={(e) =>
                        setEditData((d) => ({ ...d, abv: Number(e.target.value) }))
                      }
                      className="w-full text-xs rounded border-gray-300 focus:border-amber-500 focus:ring-amber-500"
                    />
                  </td>
                  <td className="px-4 py-2 text-right text-gray-400">—</td>
                  <td className="px-4 py-2 text-right space-x-2">
                    <button
                      onClick={() => saveEdit(entry.id)}
                      className="text-xs text-green-700 hover:underline"
                    >
                      Save
                    </button>
                    <button
                      onClick={cancelEdit}
                      className="text-xs text-gray-500 hover:underline"
                    >
                      Cancel
                    </button>
                  </td>
                </tr>
              ) : (
                <tr key={entry.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 text-gray-700 whitespace-nowrap">
                    {new Date(entry.timestamp).toLocaleString()}
                  </td>
                  <td className="px-4 py-3 text-gray-900">{entry.beerName}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{entry.volumeMl}</td>
                  <td className="px-4 py-3 text-right text-gray-700">{entry.abv}</td>
                  <td className="px-4 py-3 text-right text-gray-700">
                    {entry.standardDrinks != null ? entry.standardDrinks.toFixed(2) : '—'}
                  </td>
                  <td className="px-4 py-3 text-right space-x-3">
                    <button
                      onClick={() => startEdit(entry)}
                      className="text-xs text-blue-600 hover:underline"
                    >
                      Edit
                    </button>
                    {deletingId === entry.id ? (
                      <>
                        <span className="text-xs text-gray-500">Delete?</span>
                        <button
                          onClick={() => confirmDelete(entry.id)}
                          className="text-xs text-red-600 hover:underline"
                        >
                          Yes
                        </button>
                        <button
                          onClick={() => setDeletingId(null)}
                          className="text-xs text-gray-500 hover:underline"
                        >
                          No
                        </button>
                      </>
                    ) : (
                      <button
                        onClick={() => {
                          setDeletingId(entry.id)
                          setActionError(null)
                        }}
                        className="text-xs text-red-500 hover:underline"
                      >
                        Delete
                      </button>
                    )}
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      </div>

      {!loading && entries.length === 0 && (
        <p className="px-4 py-6 text-center text-gray-400 text-sm">No entries found.</p>
      )}

      {/* Pagination */}
      <div className="mt-4 flex items-center justify-between text-sm text-gray-600">
        <button
          onClick={onPrev}
          disabled={page === 0}
          className="px-3 py-1 rounded border border-gray-300 disabled:opacity-40 hover:bg-gray-100"
        >
          Previous
        </button>
        <span>
          Page {page + 1} of {Math.max(totalPages, 1)}
        </span>
        <button
          onClick={onNext}
          disabled={page >= totalPages - 1}
          className="px-3 py-1 rounded border border-gray-300 disabled:opacity-40 hover:bg-gray-100"
        >
          Next
        </button>
      </div>
    </div>
  )
}
