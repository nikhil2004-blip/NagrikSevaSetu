import { Outlet, NavLink, useNavigate } from 'react-router-dom'
import { LayoutDashboard, Building2, BarChart3, ClipboardList, LogOut, Lock, Building } from 'lucide-react'
import { useAuth } from '../context/AuthContext.jsx'
import { cn } from '../components/ui.jsx'

function navClass(isActive, forceActive = false) {
  const active = isActive || forceActive
  return cn(
    "flex items-center gap-4 px-4 py-2 rounded transition-colors font-label-md text-label-md",
    active 
      ? "bg-primary-container text-on-primary-container" 
      : "text-on-surface-variant hover:bg-surface-container"
  )
}

function mobileNavClass(isActive, forceActive = false) {
  const active = isActive || forceActive
  return cn(
    "flex flex-col items-center justify-center rounded-full px-4 py-1 transition-colors",
    active 
      ? "bg-primary-container text-on-primary-container" 
      : "text-on-surface-variant"
  )
}

export default function AppLayout() {
  const navigate  = useNavigate()
  const { user, isAuthenticated, logout } = useAuth()


  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  return (
    <div className="min-h-screen bg-background font-body-md text-body-md flex flex-col">
      {/* ── TopAppBar ─────────────────────────────────── */}
      <header className="fixed top-0 left-0 w-full z-50 flex items-center px-4 md:px-margin-desktop h-16 bg-surface border-b border-outline-variant shadow-sm">
        <div className="flex items-center gap-2">
          <Building className="text-primary w-6 h-6" />
          <h1 className="font-headline-sm text-headline-sm font-bold text-primary hidden md:block">NagrikSevaSetu</h1>
          <h1 className="font-headline-sm text-headline-sm font-bold text-primary md:hidden">NSS</h1>
        </div>
        <div className="ml-auto flex items-center gap-4">
          {isAuthenticated && (
            <div className="text-right hidden sm:block mr-4">
              <p className="font-label-md text-label-md text-on-surface leading-none">{user.name}</p>
              <p className="font-label-sm text-label-sm text-on-surface-variant capitalize">{user.role.replace('_', ' ')}</p>
            </div>
          )}
          {isAuthenticated && (
            <button 
              onClick={handleLogout}
              className="text-error hover:bg-error-container p-2 rounded-full transition-colors flex items-center gap-2 font-label-md text-label-md"
              title="Logout"
            >
              <LogOut size={20} />
            </button>
          )}
        </div>
      </header>

      {/* ── Desktop Sidebar ─────────────────────────────────── */}
      <div className="hidden md:flex fixed left-0 top-16 h-[calc(100vh-64px)] w-64 bg-surface-container-lowest border-r border-outline-variant p-6 flex-col z-40">
        <nav className="flex flex-col gap-2 flex-1">
          {/* Dashboard */}
          {isAuthenticated && (user.role === 'admin' || user.role === 'main_officer') ? (
            <NavLink to="/admin/dashboard" className={({ isActive }) => navClass(isActive)}>
              <LayoutDashboard size={20} /> Dashboard
            </NavLink>
          ) : user?.role === 'department_staff' && user?.deptCategory ? (
            <NavLink
              to={`/department/${user.deptCategory}/dashboard`}
              className={({ isActive }) => navClass(isActive)}
            >
              <LayoutDashboard size={20} /> My Department
            </NavLink>
          ) : (
            <div className="flex items-center justify-between px-4 py-2 rounded text-outline cursor-not-allowed select-none font-label-md text-label-md">
              <div className="flex items-center gap-4"><LayoutDashboard size={20} /> Dashboard</div>
              <Lock size={16} />
            </div>
          )}

          {/* Departments - Only show if unauthenticated since it's the login page now */}
          {!isAuthenticated && (
            <NavLink
              to="/login"
              className={({ isActive }) => navClass(isActive)}
            >
              <Building2 size={20} /> Login
            </NavLink>
          )}

          {/* Analytics */}
          {isAuthenticated ? (
            <NavLink to="/analytics" className={({ isActive }) => navClass(isActive)}>
              <BarChart3 size={20} /> Analytics
            </NavLink>
          ) : (
            <div className="flex items-center justify-between px-4 py-2 rounded text-outline cursor-not-allowed select-none font-label-md text-label-md">
              <div className="flex items-center gap-4"><BarChart3 size={20} /> Analytics</div>
              <Lock size={16} />
            </div>
          )}

          {/* History */}
          {isAuthenticated ? (
            <NavLink to="/history" className={({ isActive }) => navClass(isActive)}>
              <ClipboardList size={20} /> History
            </NavLink>
          ) : (
            <div className="flex items-center justify-between px-4 py-2 rounded text-outline cursor-not-allowed select-none font-label-md text-label-md">
              <div className="flex items-center gap-4"><ClipboardList size={20} /> History</div>
              <Lock size={16} />
            </div>
          )}
        </nav>
      </div>

      {/* ── Mobile BottomNavBar ─────────────────────────────── */}
      <nav className="fixed bottom-0 left-0 w-full z-50 flex justify-around items-center px-4 py-2 bg-surface-container-lowest border-t border-outline-variant md:hidden">
        {isAuthenticated && (user.role === 'admin' || user.role === 'main_officer') ? (
          <NavLink to="/admin/dashboard" className={({ isActive }) => mobileNavClass(isActive)}>
            <LayoutDashboard size={24} />
            <span className="font-label-sm text-label-sm mt-1">Dash</span>
          </NavLink>
        ) : user?.role === 'department_staff' && user?.deptCategory ? (
          <NavLink to={`/department/${user.deptCategory}/dashboard`} className={({ isActive }) => mobileNavClass(isActive)}>
            <LayoutDashboard size={24} />
            <span className="font-label-sm text-label-sm mt-1">Dept</span>
          </NavLink>
        ) : null}

        {!isAuthenticated && (
          <NavLink to="/login" className={({ isActive }) => mobileNavClass(isActive)}>
            <Building2 size={24} />
            <span className="font-label-sm text-label-sm mt-1">Login</span>
          </NavLink>
        )}

        {isAuthenticated && (
          <NavLink to="/analytics" className={({ isActive }) => mobileNavClass(isActive)}>
            <BarChart3 size={24} />
            <span className="font-label-sm text-label-sm mt-1">Stats</span>
          </NavLink>
        )}

        {isAuthenticated && (
          <NavLink to="/history" className={({ isActive }) => mobileNavClass(isActive)}>
            <ClipboardList size={24} />
            <span className="font-label-sm text-label-sm mt-1">History</span>
          </NavLink>
        )}
      </nav>

      {/* ── Main Content Area ────────────────────────── */}
      <main className="pt-24 pb-24 md:pb-8 px-4 md:px-margin-desktop md:ml-64 max-w-container-max mx-auto flex-1">
        <Outlet />
      </main>
    </div>
  )
}
