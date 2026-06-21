import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type { AdminUser } from '@/types/doctor';

interface AuthState {
  token: string | null;
  admin: AdminUser | null;
  rememberMe: boolean;
  setAuth: (token: string, admin: AdminUser, rememberMe?: boolean) => void;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      admin: null,
      rememberMe: false,
      setAuth: (token, admin, rememberMe = false) =>
        set({ token, admin, rememberMe }),
      logout: () => set({ token: null, admin: null, rememberMe: false }),
    }),
    {
      name: 'headsapp-admin-auth',
      partialize: (state) =>
        state.rememberMe
          ? { token: state.token, admin: state.admin, rememberMe: state.rememberMe }
          : { rememberMe: state.rememberMe },
    },
  ),
);
