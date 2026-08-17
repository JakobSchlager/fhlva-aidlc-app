import { useState, useEffect, useCallback } from 'react'
import { getWarnings, acknowledgeWarning, type Warning } from '@/services/api'

const POLL_INTERVAL_MS = 60_000

function warningLabel(type: Warning['type']): string {
  return type === 'DAILY_EXCEEDED' ? 'Daily limit exceeded' : 'Weekly limit exceeded'
}

export default function NotificationsPanel() {
  const [warnings, setWarnings] = useState<Warning[]>([])

  const fetchWarnings = useCallback(async () => {
    try {
      const res = await getWarnings('ACTIVE')
      setWarnings(res.data.content)
    } catch {
      // silently ignore — don't disrupt the page
    }
  }, [])

  useEffect(() => {
    fetchWarnings()
    const interval = setInterval(fetchWarnings, POLL_INTERVAL_MS)
    return () => clearInterval(interval)
  }, [fetchWarnings])

  const handleAcknowledge = async (id: string) => {
    try {
      await acknowledgeWarning(id)
      setWarnings((prev) => prev.filter((w) => w.id !== id))
    } catch {
      // silently ignore
    }
  }

  return (
    <div data-testid="notifications-panel" className="space-y-2">
      {warnings.map((w) => (
        <div
          key={w.id}
          role="alert"
          className="flex items-center justify-between rounded-md bg-yellow-50 border border-yellow-300 px-4 py-3"
        >
          <div>
            <p className="text-sm font-medium text-yellow-800">{warningLabel(w.type)}</p>
            <p className="text-xs text-yellow-600 mt-0.5">
              Triggered at {new Date(w.triggeredAt).toLocaleString()}
            </p>
          </div>
          <button
            onClick={() => handleAcknowledge(w.id)}
            className="ml-4 flex-shrink-0 text-xs font-medium text-yellow-800 bg-yellow-200 hover:bg-yellow-300 px-3 py-1 rounded"
          >
            Acknowledge
          </button>
        </div>
      ))}
    </div>
  )
}
