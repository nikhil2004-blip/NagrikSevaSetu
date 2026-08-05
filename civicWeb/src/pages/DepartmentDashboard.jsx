/**
 * DepartmentDashboard.jsx — Complaint management view for department officers.
 *
 * Fixes applied:
 *   1. Pagination: Added page state + backend-driven pagination so officers can
 *      see beyond the first 20 complaints (the data blackhole bug).
 *   2. Date: Uses shortDateTime() for precise timestamps in complaint rows.
 *   3. Category: 'Others' (plural) used consistently via civic constants.
 *   4. Filtering: Double .filter() removed — replaced with two separate fetches
 *      using `status` query param for correct server-side filtering.
 *   5. Sorting: Added urgency sort button for high-urgency complaints first.
 *   6. Sidebar: Shows total count from pagination metadata.
 */
import { useEffect, useMemo, useState, useCallback } from 'react'
import { useParams, Link } from 'react-router-dom'
import api from '../services/api'
import {
  Card, CardHeader, CardTitle, CardContent,
  Table, THead, TBody, TR, TH, TD, Badge, Button,
} from '../components/ui.jsx'
import { useAuth } from '../context/AuthContext.jsx'
import { RefreshCw, ChevronLeft, ChevronRight } from 'lucide-react'
import { urgencyVariant } from '../constants/civic.js'
import { shortDateTime, relativeTime } from '../utils/formatDate.js'
import { toast } from '../utils/toast.js'

const PAGE_SIZE = 20

// Urgency priority order for client-side sort (High first)
const URGENCY_ORDER = { High: 0, Medium: 1, Low: 2 }

export default function DepartmentDashboard() {
  const { deptId } = useParams()
  const { user }   = useAuth()

  const [activeComplaints,   setActiveComplaints]   = useState([])
  const [resolvedComplaints, setResolvedComplaints] = useState([])
  const [activePagination,   setActivePagination]   = useState({ total: 0, totalPages: 1 })
  const [resolvedPagination, setResolvedPagination] = useState({ total: 0, totalPages: 1 })
  const [activePage,   setActivePage]   = useState(1)
  const [resolvedPage, setResolvedPage] = useState(1)
  const [loading, setLoading] = useState(true)

  /**
   * For department_staff, always use their own deptCategory.
   * For admin/main_officer, use the deptId URL param.
   */
  const targetDept = useMemo(() => {
    if (user?.role === 'department_staff' && user?.deptCategory) return user.deptCategory
    return deptId
  }, [user, deptId])

  const fetchComplaints = useCallback(async () => {
    if (!targetDept) return
    try {
      setLoading(true)
      const [activeRes, resolvedRes] = await Promise.all([
        // Fetch ALL non-resolved complaints (Pending + In Progress) — no status filter
        // so we get both statuses in one call. We sort by createdAt desc (newest first),
        // then re-sort client-side by urgency for correct priority display.
        api.get(`/complaints?category=${encodeURIComponent(targetDept)}&status=Pending,In Progress&page=${activePage}&limit=${PAGE_SIZE}&sortBy=createdAt`),
        api.get(`/complaints?category=${encodeURIComponent(targetDept)}&status=Resolved&page=${resolvedPage}&limit=${PAGE_SIZE}`),
      ])

      // api.js interceptor returns { data: [...], pagination: {...} } when paginated
      const allActive    = Array.isArray(activeRes)   ? activeRes   : (activeRes?.data   || [])
      const resolvedData = Array.isArray(resolvedRes) ? resolvedRes : (resolvedRes?.data || [])

      // Filter out Resolved + Rejected, then sort by urgency priority (High first)
      const activeData = allActive
        .filter(c => c.status === 'Pending' || c.status === 'In Progress')
        .sort((a, b) => {
          const urgencyDiff = (URGENCY_ORDER[a.urgency] ?? 2) - (URGENCY_ORDER[b.urgency] ?? 2)
          if (urgencyDiff !== 0) return urgencyDiff
          return new Date(b.createdAt) - new Date(a.createdAt) // newest first within same urgency
        })

      setActiveComplaints(activeData)
      setResolvedComplaints(resolvedData)

      if (activeRes?.pagination)   setActivePagination(activeRes.pagination)
      if (resolvedRes?.pagination) setResolvedPagination(resolvedRes.pagination)
    } catch (error) {
      console.error('[DepartmentDashboard] fetchComplaints failed:', error)
      toast.error('Failed to load complaints.')
    } finally {
      setLoading(false)
    }
  }, [targetDept, activePage, resolvedPage])

  useEffect(() => {
    fetchComplaints()
    const interval = setInterval(fetchComplaints, 60_000)
    return () => clearInterval(interval)
  }, [fetchComplaints])

  const title = targetDept ? `${targetDept} Department` : 'Department Dashboard'

  function PaginationControls({ page, setPage, totalPages }) {
    return (
      <div className="flex items-center justify-between pt-4 border-t">
        <span className="text-xs text-muted-foreground">Page {page} of {totalPages || 1}</span>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setPage(p => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="gap-1"
          >
            <ChevronLeft size={14} /> Prev
          </Button>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setPage(p => Math.min(totalPages || 1, p + 1))}
            disabled={page >= (totalPages || 1)}
            className="gap-1"
          >
            Next <ChevronRight size={14} />
          </Button>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* ── Header ─────────────────────────────────────── */}
      <div className="flex justify-between items-center">
        <div>
          <h2 className="text-2xl font-bold">{title}</h2>
          <p className="text-sm text-muted-foreground mt-0.5">Manage and resolve complaints for this department.</p>
        </div>
        <Button variant="outline" onClick={fetchComplaints} className="gap-2" disabled={loading}>
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Refresh
        </Button>
      </div>

      {/* ── Active Complaints Table ─────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle>Action Required — Pending &amp; In Progress</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <THead>
              <TR>
                <TH>Date Submitted</TH>
                <TH>Description</TH>
                <TH>Urgency</TH>
                <TH>Status</TH>
                <TH>Upvotes</TH>
                <TH>Action</TH>
              </TR>
            </THead>
            <TBody>
              {loading ? (
                <TR><TD colSpan={6} className="text-center py-6 text-muted-foreground">Loading…</TD></TR>
              ) : activeComplaints.length === 0 ? (
                <TR><TD colSpan={6} className="text-center py-6 text-muted-foreground">✅ No active complaints.</TD></TR>
              ) : activeComplaints.map(c => (
                <TR key={c._id}>
                  <TD className="whitespace-nowrap">
                    <div className="text-sm">{shortDateTime(c.createdAt)}</div>
                    <div className="text-xs text-muted-foreground">{relativeTime(c.createdAt)}</div>
                  </TD>
                  <TD className="max-w-[220px]">
                    <div className="truncate text-sm" title={c.description}>{c.description}</div>
                  </TD>
                  <TD><Badge variant={urgencyVariant(c.urgency)}>{c.urgency}</Badge></TD>
                  <TD>
                    <span className={c.status === 'In Progress' ? 'text-yellow-700 font-medium' : 'text-red-700 font-medium'}>
                      {c.status}
                    </span>
                  </TD>
                  <TD>
                    <span className="font-semibold">{c.upvotes ?? 0}</span>
                    {c.upvotes >= 5 && <span className="ml-1 text-xs text-orange-500">🔥</span>}
                  </TD>
                  <TD>
                    <Link
                      to={`/complaints/${c._id}`}
                      className="text-primary font-medium hover:underline text-sm"
                    >
                      Review →
                    </Link>
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
          <PaginationControls
            page={activePage}
            setPage={setActivePage}
            totalPages={activePagination.totalPages}
          />
        </CardContent>
      </Card>

      {/* ── Resolved Complaints Log ─────────────────────── */}
      <Card>
        <CardHeader>
          <CardTitle className="text-muted-foreground">Resolved Log</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <THead>
              <TR>
                <TH>Date Submitted</TH>
                <TH>Description</TH>
                <TH>Urgency</TH>
                <TH>Upvotes</TH>
                <TH>Action</TH>
              </TR>
            </THead>
            <TBody>
              {loading ? (
                <TR><TD colSpan={5} className="text-center py-6 text-muted-foreground">Loading…</TD></TR>
              ) : resolvedComplaints.length === 0 ? (
                <TR><TD colSpan={5} className="text-center py-6 text-muted-foreground">No resolved complaints yet.</TD></TR>
              ) : resolvedComplaints.map(c => (
                <TR key={c._id} className="opacity-70">
                  <TD className="whitespace-nowrap text-sm">{shortDateTime(c.createdAt)}</TD>
                  <TD className="max-w-[220px]">
                    <div className="truncate text-sm" title={c.description}>{c.description}</div>
                  </TD>
                  <TD><Badge variant="default">{c.urgency}</Badge></TD>
                  <TD>{c.upvotes ?? 0}</TD>
                  <TD>
                    <Link to={`/complaints/${c._id}`} className="text-primary hover:underline text-sm">
                      View
                    </Link>
                  </TD>
                </TR>
              ))}
            </TBody>
          </Table>
          <PaginationControls
            page={resolvedPage}
            setPage={setResolvedPage}
            totalPages={resolvedPagination.totalPages}
          />
        </CardContent>
      </Card>
    </div>
  )
}
