import { BrowserRouter, Routes, Route, Navigate, Outlet, useParams } from 'react-router-dom'
import { Component } from 'react'
import { AuthProvider, useAuth } from './context/AuthContext.jsx'
import AppLayout from './layouts/AppLayout.jsx'
import Dashboard from './pages/Dashboard.jsx'
import Departments from './pages/Departments.jsx' // Will act as Login
import DepartmentDashboard from './pages/DepartmentDashboard.jsx'
import ComplaintDetail from './pages/ComplaintDetail.jsx'
import Analytics from './pages/Analytics.jsx'
import History from './pages/History.jsx'
import ChangePassword from './pages/ChangePassword.jsx'
import NotFound from './pages/NotFound.jsx'
// Placeholder imports, to be implemented
// import AdminComplaints from './pages/AdminComplaints.jsx'
// import DepartmentComplaints from './pages/DepartmentComplaints.jsx'
// import Unauthorized from './pages/Unauthorized.jsx'

class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false };
  }
  static getDerivedStateFromError(_error) {
    return { hasError: true };
  }
  componentDidCatch(error, errorInfo) {
    console.error("ErrorBoundary caught an error", error, errorInfo);
  }
  render() {
    if (this.state.hasError) {
      return (
        <div className="flex h-screen w-full items-center justify-center bg-surface text-on-surface p-6 text-center">
          <div className="max-w-md space-y-4">
            <h1 className="text-3xl font-bold text-error">System Error</h1>
            <p className="text-on-surface-variant">A component crashed. Our engineers have been notified.</p>
            <button onClick={() => window.location.reload()} className="bg-primary text-on-primary px-4 py-2 rounded">
              Reload Application
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

function ProtectedLayout({ allowedRoles }) {
  const { user, isAuthenticated, logout } = useAuth()
  const { deptId } = useParams()
  
  if (!isAuthenticated) return <Navigate to="/login" replace />
  
  // Citizen guard
  if (user.role === 'citizen') {
    logout()
    return <Navigate to="/unauthorized" replace />
  }

  // Role whitelist
  if (allowedRoles && !allowedRoles.includes(user.role)) return <Navigate to="/unauthorized" replace />
  
  // Department logic isolation guard
  if (deptId && user.role === 'department_staff' && user.deptCategory !== deptId) {
    return <Navigate to="/unauthorized" replace />
  }
  
  return <Outlet />
}

function DynamicRedirect() {
  const { user, isAuthenticated } = useAuth()
  if (!isAuthenticated) return <Navigate to="/login" replace />
  if (user.role === 'admin' || user.role === 'main_officer') return <Navigate to="/admin/dashboard" replace />
  if (user.role === 'department_staff' && user.deptCategory) return <Navigate to={`/department/${user.deptCategory}/dashboard`} replace />
  return <Navigate to="/login" replace />
}

export default function App() {
  return (
    <ErrorBoundary>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Departments />} />
            <Route path="/change-password" element={<ChangePassword />} />
            <Route path="/unauthorized" element={
              <div className="flex h-screen w-full items-center justify-center bg-surface">
                <h1 className="text-3xl text-error font-bold">401 Unauthorized</h1>
              </div>
            } />
            
            <Route element={<AppLayout />}>
              <Route path="/" element={<DynamicRedirect />} />

              {/* Admin & Main Officer Routes */}
              <Route element={<ProtectedLayout allowedRoles={["admin", "main_officer"]} />}>
                <Route path="/admin/dashboard" element={<Dashboard />} />
                <Route path="/admin/complaints" element={<Analytics />} />
                <Route path="/analytics" element={<Analytics />} />
              </Route>

              {/* Department Staff Routes */}
              <Route element={<ProtectedLayout allowedRoles={["admin", "main_officer", "department_staff"]} />}>
                <Route path="/department/:deptId/dashboard" element={<DepartmentDashboard />} />
                <Route path="/department/:deptId/complaints" element={<Analytics />} />
              </Route>

              {/* Shared Routes */}
              <Route element={<ProtectedLayout allowedRoles={["admin", "main_officer", "department_staff"]} />}>
                <Route path="/complaints/:complaintId" element={<ComplaintDetail />} />
                <Route path="/history" element={<History />} />
              </Route>
            </Route>
            
            {/* Catch-all */}
            <Route path="*" element={<NotFound />} />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </ErrorBoundary>
  )
}
