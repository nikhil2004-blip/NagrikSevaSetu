/**
 * History.jsx — Complete Complaint History Page
 *
 * Features:
 *  - Full paginated list of all complaints (server-side pagination)
 *  - Filters: Department/Category, Status, Urgency, Date range, search by ID
 *  - Sort: Newest / Oldest / Most Upvoted / Urgency (High first) / Recently Updated
 *  - Colour-coded badges for status & urgency
 *  - View button links to ComplaintDetail page
 *  - URL-sync: filters are reflected in query params so the page is shareable/bookmarkable
 */
import { useEffect, useState, useCallback, useRef } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import api from '../services/api'
import {
  Card, CardHeader, CardTitle, CardContent,
  Table, THead, TBody, TR, TH, TD, Badge, Button,
} from '../components/ui.jsx'
import { useAuth } from '../context/AuthContext.jsx'
import { CATEGORIES, STATUSES, URGENCY_LEVELS } from '../constants/civic.js'
import { shortDateTime, relativeTime } from '../utils/formatDate.js'
import { toast } from '../utils/toast.js'
import {
  RefreshCw, Search, Filter, ChevronLeft, ChevronRight,
  ArrowUpDown, Clock, Flame, TrendingUp, AlertTriangle, X, FileText,
} from 'lucide-react'

// ── Design tokens (match Analytics palette) ────────────────────
const URGENCY_DOT = { High: 'bg-red-500', Medium: 'bg-amber-400', Low: 'bg-emerald-400' }
const STATUS_DOT  = {
  Pending: 'bg-red-400', 'In Progress': 'bg-amber-400',
  Resolved: 'bg-emerald-500', Rejected: 'bg-slate-400',
}

// Sort options
const SORT_OPTIONS = [
  { value: 'createdAt_desc',  label: 'Newest First',       icon: Clock },
  { value: 'createdAt_asc',   label: 'Oldest First',       icon: Clock },
  { value: 'updatedAt_desc',  label: 'Recently Updated',   icon: RefreshCw },
  { value: 'upvotes_desc',    label: 'Most Upvoted',       icon: TrendingUp },
  { value: 'urgency_high',    label: 'Urgency (High→Low)', icon: Flame },
]

const PAGE_SIZES = [10, 20, 50]

// ── Skeleton Row ───────────────────────────────────────────────
const SkeletonRow = () => (
  <TR>
    {[1, 2, 3, 4, 5, 6].map(i => (
      <TD key={i}>
        <div className="h-4 bg-gray-100 rounded animate-pulse" style={{ width: `${50 + Math.random() * 40}%` }} />
      </TD>
    ))}
  </TR>
)

// ── Filter Chip (active filter pill) ──────────────────────────
const FilterChip = ({ label, onRemove }) => (
  <span className="inline-flex items-center gap-1 pl-2.5 pr-1.5 py-1 rounded-full bg-indigo-100 text-indigo-700 text-xs font-medium">
    {label}
    <button onClick={onRemove} className="hover:bg-indigo-200 rounded-full p-0.5 transition-colors">
      <X size={10} />
    </button>
  </span>
)

// ── Select helper ──────────────────────────────────────────────
const Sel = ({ value, onChange, children, cls = '' }) => (
  <select
    value={value}
    onChange={e => onChange(e.target.value)}
    className={`border border-gray-200 rounded-xl text-sm px-3 py-2 bg-white shadow-sm
      focus:ring-2 focus:ring-indigo-300 focus:border-indigo-400 outline-none
      text-gray-700 font-medium cursor-pointer hover:border-gray-300 transition-colors ${cls}`}
  >
    {children}
  </select>
)

// ═══════════════════════════════════════════════════════════════
// History Page
// ═══════════════════════════════════════════════════════════════
export default function History() {
  const navigate   = useNavigate()
  const { user }   = useAuth()
  const [params, setParams] = useSearchParams()

  const isAdmin = !user || user.role === 'admin' || user.role === 'main_officer'

  // ── Filter state (initialise from URL params) ──────────────
  const [category, setCategory]   = useState(params.get('category') || 'All')
  const [status,   setStatus]     = useState(params.get('status')   || 'All')
  const [urgency,  setUrgency]    = useState(params.get('urgency')  || 'All')
  const [sort,     setSort]       = useState(params.get('sort')     || 'createdAt_desc')
  const [days,     setDays]       = useState(params.get('days')     || 'all')
  const [page,     setPage]       = useState(Number(params.get('page')) || 1)
  const [pageSize, setPageSize]   = useState(Number(params.get('limit')) || 20)
  const [search,   setSearch]     = useState(params.get('search')   || '')
  const searchInput               = useRef(null)

  // ── Data state ─────────────────────────────────────────────
  const [complaints, setComplaints] = useState([])
  const [pagination, setPagination] = useState({ total: 0, totalPages: 1 })
  const [loading,    setLoading]    = useState(true)
  const [error,      setError]      = useState(null)

  // ── Build API query from current filters ───────────────────
  const buildQuery = useCallback(() => {
    const q = new URLSearchParams()
    if (category !== 'All') q.set('category', category)
    if (status   !== 'All') q.set('status',   status)
    if (urgency  !== 'All') q.set('urgency',  urgency)
    if (search.trim())       q.set('search',  search.trim())
    q.set('page',  String(page))
    q.set('limit', String(pageSize))

    // Resolve sort → backend sortBy + order
    if (sort === 'createdAt_asc')  { q.set('sortBy', 'createdAt'); q.set('order', 'asc') }
    else if (sort === 'upvotes_desc')  { q.set('sortBy', 'upvotes') }
    else if (sort === 'updatedAt_desc') { q.set('sortBy', 'updatedAt') }
    else if (sort === 'urgency_high') { q.set('sortBy', 'urgency') }
    else { q.set('sortBy', 'createdAt') } // default newest

    // Date filter
    if (days !== 'all') q.set('days', days)

    return q.toString()
  }, [category, status, urgency, sort, days, page, pageSize, search])

  // ── Sync filters → URL params ──────────────────────────────
  useEffect(() => {
    const next = new URLSearchParams()
    if (category !== 'All')   next.set('category', category)
    if (status   !== 'All')   next.set('status',   status)
    if (urgency  !== 'All')   next.set('urgency',  urgency)
    if (sort !== 'createdAt_desc') next.set('sort', sort)
    if (days !== 'all')       next.set('days',     days)
    if (page > 1)             next.set('page',     String(page))
    if (pageSize !== 20)      next.set('limit',    String(pageSize))
    if (search.trim())        next.set('search',   search.trim())
    setParams(next, { replace: true })
  }, [category, status, urgency, sort, days, page, pageSize, search, setParams])

  // ── Fetch ──────────────────────────────────────────────────
  const fetchHistory = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const res = await api.get(`/complaints?${buildQuery()}`)
      const list = Array.isArray(res) ? res : (res?.data || [])
      const pg   = res?.pagination || { total: list.length, totalPages: 1 }
      setComplaints(list)
      setPagination(pg)
    } catch (err) {
      console.error('[History] fetch failed:', err)
      setError(err.message)
      toast.error('Failed to load complaints: ' + err.message)
    } finally {
      setLoading(false)
    }
  }, [buildQuery])

  useEffect(() => { fetchHistory() }, [fetchHistory])

  // ── Reset page when filters change ────────────────────────
  const applyFilter = (setter) => (val) => {
    setter(val)
    setPage(1)
  }

  // ── Active filter chips ────────────────────────────────────
  const activeFilters = [
    category !== 'All' && { label: `Dept: ${category}`,  clear: () => applyFilter(setCategory)('All') },
    status   !== 'All' && { label: `Status: ${status}`,  clear: () => applyFilter(setStatus)('All')   },
    urgency  !== 'All' && { label: `Urgency: ${urgency}`,clear: () => applyFilter(setUrgency)('All')  },
    days     !== 'all' && { label: `Last ${days} days`,  clear: () => applyFilter(setDays)('all')     },
    search.trim()      && { label: `"${search}"`,         clear: () => { setSearch(''); setPage(1) }   },
  ].filter(Boolean)

  const clearAll = () => {
    setCategory('All'); setStatus('All'); setUrgency('All')
    setDays('all'); setSearch(''); setSort('createdAt_desc'); setPage(1)
  }

  // ── Sort state for urgency (client-side remap since backend doesn't support it directly) ─
  const displayComplaints = [...complaints].sort((a, b) => {
    if (sort === 'urgency_high') {
      const ORDER = { High: 0, Medium: 1, Low: 2 }
      return (ORDER[a.urgency] ?? 3) - (ORDER[b.urgency] ?? 3)
    }
    return 0 // already sorted server-side
  })

  return (
    <div className="space-y-5 pb-10" style={{ fontFamily: 'system-ui, -apple-system, sans-serif' }}>

      {/* ── Header ─────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <FileText size={22} className="text-indigo-500" />
            Complaint History
          </h1>
          <p className="text-sm text-gray-400 mt-0.5">
            Full searchable record of all {isAdmin ? 'city-wide' : `${user?.deptCategory} department`} complaints
          </p>
        </div>
        <button
          onClick={fetchHistory}
          disabled={loading}
          className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-indigo-600 text-white text-sm font-medium hover:bg-indigo-700 disabled:opacity-50"
        >
          <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
          {loading ? 'Loading…' : 'Refresh'}
        </button>
      </div>

      {/* ── Filter Bar ─────────────────────────────────────── */}
      <Card>
        <CardContent className="pt-4 pb-4">
          <div className="flex flex-wrap gap-3 items-end">
            {/* Search */}
            <div className="relative flex-1 min-w-[200px]">
              <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
              <input
                ref={searchInput}
                value={search}
                onChange={e => { setSearch(e.target.value); setPage(1) }}
                placeholder="Search description…"
                className="w-full pl-8 pr-3 py-2 border border-gray-200 rounded-xl text-sm focus:ring-2 focus:ring-indigo-300 focus:border-indigo-400 outline-none"
              />
              {search && (
                <button onClick={() => { setSearch(''); setPage(1) }} className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-300 hover:text-gray-500">
                  <X size={13} />
                </button>
              )}
            </div>

            {/* Category */}
            {isAdmin && (
              <Sel value={category} onChange={applyFilter(setCategory)}>
                <option value="All">All Departments</option>
                {CATEGORIES.map(c => <option key={c} value={c}>{c}</option>)}
              </Sel>
            )}

            {/* Status */}
            <Sel value={status} onChange={applyFilter(setStatus)}>
              <option value="All">All Statuses</option>
              {STATUSES.map(s => <option key={s} value={s}>{s}</option>)}
            </Sel>

            {/* Urgency */}
            <Sel value={urgency} onChange={applyFilter(setUrgency)}>
              <option value="All">All Urgency</option>
              {URGENCY_LEVELS.map(u => <option key={u} value={u}>{u}</option>)}
            </Sel>

            {/* Date range */}
            <Sel value={days} onChange={applyFilter(setDays)}>
              <option value="all">All Time</option>
              <option value="7">Last 7 Days</option>
              <option value="14">Last 14 Days</option>
              <option value="30">Last 30 Days</option>
              <option value="90">Last 3 Months</option>
            </Sel>

            {/* Sort */}
            <div className="flex items-center gap-2">
              <ArrowUpDown size={14} className="text-gray-400 shrink-0" />
              <Sel value={sort} onChange={v => { setSort(v); setPage(1) }}>
                {SORT_OPTIONS.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
              </Sel>
            </div>

            {/* Rows per page */}
            <Sel value={pageSize} onChange={v => { setPageSize(Number(v)); setPage(1) }} cls="w-20">
              {PAGE_SIZES.map(n => <option key={n} value={n}>{n} / pg</option>)}
            </Sel>

            {/* Clear all */}
            {activeFilters.length > 0 && (
              <button
                onClick={clearAll}
                className="text-xs text-gray-400 hover:text-red-500 transition-colors whitespace-nowrap flex items-center gap-1"
              >
                <X size={12} /> Clear all
              </button>
            )}
          </div>

          {/* Active filter chips */}
          {activeFilters.length > 0 && (
            <div className="flex flex-wrap gap-2 mt-3 pt-3 border-t border-gray-100">
              <span className="text-xs text-gray-400 flex items-center gap-1 mr-1">
                <Filter size={11} /> Active:
              </span>
              {activeFilters.map((f, i) => (
                <FilterChip key={i} label={f.label} onRemove={f.clear} />
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      {/* ── Results summary ─────────────────────────────────── */}
      <div className="flex items-center justify-between text-sm text-gray-500">
        <span>
          {loading ? 'Loading…' : (
            <>
              Showing <strong className="text-gray-700">{complaints.length}</strong> of{' '}
              <strong className="text-gray-700">{pagination.total}</strong> complaints
            </>
          )}
        </span>
        <span className="text-xs text-gray-400">
          Page {page} of {pagination.totalPages}
        </span>
      </div>

      {/* ── Error state ─────────────────────────────────────── */}
      {error && !loading && (
        <div className="rounded-xl bg-red-50 border border-red-200 p-4 flex items-center gap-3 text-red-700">
          <AlertTriangle size={18} />
          <span className="text-sm">{error}</span>
          <button onClick={fetchHistory} className="ml-auto text-xs underline">Retry</button>
        </div>
      )}

      {/* ── Table ───────────────────────────────────────────── */}
      <Card>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <THead>
                <TR>
                  <TH className="pl-5">Department</TH>
                  <TH>Description</TH>
                  <TH>Urgency</TH>
                  <TH>Status</TH>
                  <TH>Upvotes</TH>
                  <TH>Reported</TH>
                  <TH>Last Updated</TH>
                  <TH className="pr-5"></TH>
                </TR>
              </THead>
              <TBody>
                {loading
                  ? Array.from({ length: pageSize > 10 ? 8 : 5 }).map((_, i) => <SkeletonRow key={i} />)
                  : displayComplaints.length === 0
                    ? (
                      <TR>
                        <TD colSpan={8} className="py-16 text-center">
                          <div className="flex flex-col items-center gap-3 text-gray-300">
                            <FileText size={40} />
                            <p className="text-sm font-medium text-gray-400">No complaints match your filters</p>
                            <button onClick={clearAll} className="text-xs text-indigo-500 hover:underline">Clear filters</button>
                          </div>
                        </TD>
                      </TR>
                    )
                    : displayComplaints.map((c, idx) => (
                      <TR key={c._id} className={idx % 2 === 0 ? '' : 'bg-gray-50/50'}>
                        {/* Department */}
                        <TD className="pl-5">
                          <span className="font-semibold text-gray-800 text-sm">{c.category}</span>
                        </TD>

                        {/* Description (truncated) */}
                        <TD className="max-w-[220px]">
                          <p className="text-sm text-gray-600 truncate" title={c.description || '(no description)'}>
                            {c.voiceNoteUrl && !c.description
                              ? <span className="italic text-indigo-400 text-xs">🎙 Voice note</span>
                              : (c.description || <span className="text-gray-300 text-xs">—</span>)
                            }
                          </p>
                          {c.voiceNoteTranscript && (
                            <p className="text-xs text-indigo-400 truncate mt-0.5" title={c.voiceNoteTranscript}>
                              🔤 {c.voiceNoteTranscript}
                            </p>
                          )}
                        </TD>

                        {/* Urgency */}
                        <TD>
                          <span className={`inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full
                            ${c.urgency === 'High'   ? 'bg-red-100 text-red-700'
                            : c.urgency === 'Medium' ? 'bg-amber-100 text-amber-700'
                            : 'bg-emerald-100 text-emerald-700'}`}
                          >
                            <span className={`w-1.5 h-1.5 rounded-full ${URGENCY_DOT[c.urgency] ?? 'bg-gray-400'}`} />
                            {c.urgency}
                          </span>
                        </TD>

                        {/* Status */}
                        <TD>
                          <span className={`inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full
                            ${c.status === 'Resolved'    ? 'bg-emerald-100 text-emerald-700'
                            : c.status === 'Rejected'    ? 'bg-gray-100 text-gray-600'
                            : c.status === 'In Progress' ? 'bg-amber-100 text-amber-700'
                            : 'bg-red-100 text-red-700'}`}
                          >
                            <span className={`w-1.5 h-1.5 rounded-full ${STATUS_DOT[c.status] ?? 'bg-gray-400'}`} />
                            {c.status}
                          </span>
                        </TD>

                        {/* Upvotes */}
                        <TD>
                          <span className="text-sm text-gray-500 flex items-center gap-1">
                            <TrendingUp size={12} className="text-indigo-400" />
                            {c.upvotes ?? 0}
                          </span>
                        </TD>

                        {/* Reported */}
                        <TD>
                          <span className="text-xs text-gray-500 whitespace-nowrap" title={shortDateTime(c.createdAt)}>
                            {relativeTime(c.createdAt)}
                          </span>
                        </TD>

                        {/* Last Updated */}
                        <TD>
                          <span className="text-xs text-gray-400 whitespace-nowrap">
                            {shortDateTime(c.updatedAt)}
                          </span>
                        </TD>

                        {/* View action */}
                        <TD className="pr-5">
                          <button
                            onClick={() => navigate(`/complaints/${c._id}`)}
                            className="text-xs font-semibold text-indigo-600 hover:text-indigo-800 hover:bg-indigo-50 px-3 py-1.5 rounded-lg transition-colors whitespace-nowrap"
                          >
                            View →
                          </button>
                        </TD>
                      </TR>
                    ))}
              </TBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* ── Pagination ──────────────────────────────────────── */}
      {pagination.totalPages > 1 && (
        <div className="flex items-center justify-between gap-4">
          <button
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page <= 1 || loading}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl border border-gray-200 text-sm font-medium text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            <ChevronLeft size={15} /> Previous
          </button>

          {/* Page number pills */}
          <div className="flex items-center gap-1">
            {Array.from({ length: Math.min(pagination.totalPages, 7) }, (_, i) => {
              const pageNum = (() => {
                if (pagination.totalPages <= 7) return i + 1
                if (page <= 4) return i + 1
                if (page >= pagination.totalPages - 3) return pagination.totalPages - 6 + i
                return page - 3 + i
              })()
              return (
                <button
                  key={pageNum}
                  onClick={() => setPage(pageNum)}
                  className={`w-9 h-9 rounded-xl text-sm font-medium transition-colors
                    ${pageNum === page
                      ? 'bg-indigo-600 text-white shadow-sm'
                      : 'text-gray-500 hover:bg-gray-100'}`}
                >
                  {pageNum}
                </button>
              )
            })}
          </div>

          <button
            onClick={() => setPage(p => Math.min(pagination.totalPages, p + 1))}
            disabled={page >= pagination.totalPages || loading}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl border border-gray-200 text-sm font-medium text-gray-600 hover:bg-gray-50 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
          >
            Next <ChevronRight size={15} />
          </button>
        </div>
      )}

    </div>
  )
}
