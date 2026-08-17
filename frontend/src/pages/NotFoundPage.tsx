import { Link } from 'react-router-dom'

export default function NotFoundPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center">
        <p className="text-6xl font-bold text-amber-600">404</p>
        <h1 className="mt-4 text-2xl font-semibold text-gray-900">Page not found</h1>
        <p className="mt-2 text-gray-500">The page you are looking for does not exist.</p>
        <Link
          to="/"
          className="mt-6 inline-block px-4 py-2 bg-amber-600 text-white rounded-md text-sm hover:bg-amber-700"
        >
          Go home
        </Link>
      </div>
    </div>
  )
}
