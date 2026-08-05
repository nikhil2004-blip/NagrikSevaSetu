/**
 * AuthContext.jsx — Global authentication state for the civic web portal.
 *
 * Flow:
 *   1. Firebase Auth triggers onAuthStateChanged on every page load / sign-in / sign-out.
 *   2. If a Firebase user exists, we call /api/users/sync to get our MongoDB role info.
 *   3. We merge Firebase info + MongoDB info into a single `user` object.
 *   4. All protected routes read from this context via useAuth().
 */
import { createContext, useContext, useEffect, useMemo, useState, useCallback } from 'react'
import {
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
} from 'firebase/auth'
import { auth } from '../services/firebase'
import api from '../services/api'
import { toast } from '../utils/toast'

const AuthContext = createContext(null)

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [isLoading, setIsLoading] = useState(true)

  const syncWithBackend = useCallback(async (fbUser) => {
    try {
      const dbUser = await api.post('/users/sync', {
        name: fbUser.displayName || fbUser.email.split('@')[0],
        email: fbUser.email,
        phone: fbUser.phoneNumber || '',
      })
      return {
        uid: fbUser.uid,
        email: fbUser.email,
        id: dbUser.id,
        name: dbUser.name,
        role: dbUser.role,
        deptCategory: dbUser.deptCategory || dbUser.department || null,
      }
    } catch (error) {
      const msg = error.response?.data?.message || error.message;
      console.error('[AuthContext] Backend sync failed:', msg)
      toast.error(`Backend sync failed: ${msg}`)
      await firebaseSignOut(auth)
      return null
    }
  }, [])

  useEffect(() => {
    if (window.__PLAYWRIGHT_TEST__) {
      window.__setMockUser = (mockUser) => {
        setUser(mockUser)
        setIsLoading(false)
      }
      // If Playwright pre-injected a user
      if (window.__PLAYWRIGHT_MOCK_USER__) {
        setUser(window.__PLAYWRIGHT_MOCK_USER__)
      } else {
        setUser(null)
      }
      setIsLoading(false)
      return
    }

    const unsubscribe = onAuthStateChanged(auth, async (fbUser) => {
      if (fbUser) {
        const composedUser = await syncWithBackend(fbUser)
        setUser(composedUser)
      } else {
        setUser(null)
      }
      setIsLoading(false)
    })
    return () => unsubscribe()
  }, [syncWithBackend])

  const login = useCallback(async (email, password) => {
    if (window.__PLAYWRIGHT_TEST__) {
      if (email === 'admin@test.com' && password === 'test1234') {
        setUser({ id: 'test', name: 'Test Admin', email, role: 'admin' })
        return
      }
      if (email === 'dept@test.com' && password === 'test1234') {
        setUser({ id: 'test2', name: 'Test Dept', email, role: 'department_staff', deptCategory: 'Sanitation' })
        return
      }
      throw new Error('Invalid credentials. Please check your email and password.')
    }

    try {
      await signInWithEmailAndPassword(auth, email, password)
    } catch (error) {
      let message = 'An unexpected error occurred during login.'
      if (error.code === 'auth/invalid-credential' || error.code === 'auth/wrong-password' || error.code === 'auth/user-not-found') {
        message = 'Invalid credentials. Please check your email and password.'
      } else if (error.code === 'auth/network-request-failed') {
        message = 'Network timeout. Please check your internet connection.'
      } else if (error.code === 'auth/too-many-requests') {
        message = 'Too many failed login attempts. Please try again later.'
      }
      throw new Error(message)
    }
  }, [])

  const logout = useCallback(async () => {
    if (window.__PLAYWRIGHT_TEST__) {
      setUser(null)
      return
    }
    
    try {
      await firebaseSignOut(auth)
      setUser(null)
    } catch (err) {
      toast.error('Failed to log out. Please try again.')
      console.error('[AuthContext] Logout failed:', err)
    }
  }, [])

  const value = useMemo(
    () => ({
      user,
      isLoading,
      isAuthenticated: !!user,
      userRole: user?.role || null,
      login,
      logout
    }),
    [user, isLoading, login, logout]
  )

  return (
    <AuthContext.Provider value={value}>
      {!isLoading && children}
    </AuthContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>')
  return ctx
}
