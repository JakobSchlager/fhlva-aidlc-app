import { useState, type FormEvent } from 'react'
import { createEntry, type TrackingEntryInput } from '@/services/api'

interface BeerEntryFormProps {
  onEntryCreated?: () => void
}

export default function BeerEntryForm({ onEntryCreated }: BeerEntryFormProps) {
  const [beerName, setBeerName] = useState('')
  const [volumeMl, setVolumeMl] = useState<string>('330')
  const [abv, setAbv] = useState<string>('5.0')
  const [timestamp, setTimestamp] = useState('')
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    setError(null)
    setSuccess(false)
    setLoading(true)

    const data: TrackingEntryInput = {
      beerName: beerName.trim(),
      volumeMl: Number(volumeMl),
      abv: Number(abv),
    }
    if (timestamp) {
      data.timestamp = new Date(timestamp).toISOString()
    }

    try {
      await createEntry(data)
      setSuccess(true)
      setBeerName('')
      setVolumeMl('330')
      setAbv('5.0')
      setTimestamp('')
      onEntryCreated?.()
    } catch (err: unknown) {
      const message =
        (err as { response?: { data?: { message?: string } } })?.response?.data?.message ??
        'Failed to log entry.'
      setError(message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <label htmlFor="beerName" className="block text-sm font-medium text-gray-700 mb-1">
            Beer Name
          </label>
          <input
            id="beerName"
            type="text"
            required
            placeholder="e.g. Pilsner Urquell"
            value={beerName}
            onChange={(e) => setBeerName(e.target.value)}
            className="block w-full rounded-md border-gray-300 shadow-sm focus:border-amber-500 focus:ring-amber-500 sm:text-sm"
          />
        </div>
        <div>
          <label htmlFor="volumeMl" className="block text-sm font-medium text-gray-700 mb-1">
            Volume (ml)
          </label>
          <input
            id="volumeMl"
            type="number"
            required
            min="1"
            max="5000"
            value={volumeMl}
            onChange={(e) => setVolumeMl(e.target.value)}
            className="block w-full rounded-md border-gray-300 shadow-sm focus:border-amber-500 focus:ring-amber-500 sm:text-sm"
          />
        </div>
        <div>
          <label htmlFor="abv" className="block text-sm font-medium text-gray-700 mb-1">
            ABV (%)
          </label>
          <input
            id="abv"
            type="number"
            required
            min="0"
            max="100"
            step="0.1"
            value={abv}
            onChange={(e) => setAbv(e.target.value)}
            className="block w-full rounded-md border-gray-300 shadow-sm focus:border-amber-500 focus:ring-amber-500 sm:text-sm"
          />
        </div>
        <div className="sm:col-span-2">
          <label htmlFor="timestamp" className="block text-sm font-medium text-gray-700 mb-1">
            Date &amp; Time <span className="text-gray-400">(optional — defaults to now)</span>
          </label>
          <input
            id="timestamp"
            type="datetime-local"
            value={timestamp}
            onChange={(e) => setTimestamp(e.target.value)}
            className="block w-full rounded-md border-gray-300 shadow-sm focus:border-amber-500 focus:ring-amber-500 sm:text-sm"
          />
        </div>
      </div>
      {success && (
        <div className="rounded-md bg-green-50 border border-green-200 p-3 text-sm text-green-700">
          Entry logged successfully!
        </div>
      )}
      {error && (
        <div className="rounded-md bg-red-50 border border-red-200 p-3 text-sm text-red-700">
          {error}
        </div>
      )}
      <button
        type="submit"
        disabled={loading}
        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-amber-600 hover:bg-amber-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-amber-500 disabled:opacity-50"
      >
        {loading ? 'Logging…' : 'Log Beer'}
      </button>
    </form>
  )
}
